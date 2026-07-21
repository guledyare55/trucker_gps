import httpx
import json
from typing import Optional
from app.core.config import settings
from app.core.database import get_redis


class RoutingService:
    """
    Truck routing via OpenRouteService (ORS).
    Free tier: 2,000 direction requests/day.
    ORS profile: driving-hgv (Heavy Goods Vehicle) for truck routing.
    Supports height, weight, length, width restrictions.
    """

    ORS_DIRECTIONS_URL = f"{settings.ORS_BASE_URL}/v2/directions/driving-hgv"
    ORS_GEOCODE_URL = f"{settings.ORS_BASE_URL}/geocode/search"
    ORS_MATRIX_URL = f"{settings.ORS_BASE_URL}/v2/matrix/driving-hgv"

    def __init__(self):
        self.headers = {
            "Authorization": settings.ORS_API_KEY,
            "Content-Type": "application/json",
            "Accept": "application/json, application/geo+json",
        }

    async def get_route(
        self,
        start_lon: float,
        start_lat: float,
        end_lon: float,
        end_lat: float,
        height_meters: float = 4.11,
        weight_kg: float = 36287.0,
        length_meters: float = 22.86,
        width_meters: float = 2.59,
        axle_load_kg: float = 9000.0,
        hazmat: bool = False,
        avoid_features: Optional[list[str]] = None,
        waypoints: Optional[list[list[float]]] = None,
    ) -> dict:
        """
        Get truck-optimized route from ORS.
        Returns GeoJSON with route geometry, turn-by-turn steps, duration, distance.
        """
        redis = await get_redis()
        cache_key = f"route:{start_lon:.4f},{start_lat:.4f}:{end_lon:.4f},{end_lat:.4f}:{height_meters}:{weight_kg}:{hazmat}"

        # Check cache
        cached = await redis.get(cache_key)
        if cached:
            return json.loads(cached)

        coordinates = [[start_lon, start_lat]]
        if waypoints:
            coordinates.extend(waypoints)
        coordinates.append([end_lon, end_lat])

        vehicle_type = "hgv"  # heavy goods vehicle

        payload = {
            "coordinates": coordinates,
            "instructions": True,
            "instructions_format": "text",
            "language": "en",
            "units": "mi",
            "geometry": True,
            "geometry_format": "geojson",
            "elevation": True,
            "extra_info": ["tollways", "surface", "waytype", "steepness", "restrictions"],
            "options": {
                "vehicle_type": vehicle_type,
                "profile_params": {
                    "restrictions": {
                        "height": height_meters,
                        "weight": weight_kg / 1000,  # ORS expects tonnes
                        "length": length_meters,
                        "width": width_meters,
                        "axle_load": axle_load_kg / 1000,
                        "hazmat": hazmat,
                    }
                },
            },
        }

        if avoid_features:
            payload["options"]["avoid_features"] = avoid_features  # e.g. ["tollways", "ferries"]

        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                self.ORS_DIRECTIONS_URL,
                headers=self.headers,
                json=payload,
            )
            resp.raise_for_status()
            data = resp.json()

        # Parse and enrich response
        result = self._parse_ors_response(data)

        # Cache the result
        await redis.setex(cache_key, settings.ROUTE_CACHE_TTL, json.dumps(result))
        return result

    def _parse_ors_response(self, data: dict) -> dict:
        """Parse ORS response into app-friendly format."""
        if not data.get("routes"):
            return {"error": "No route found"}

        route = data["routes"][0]
        summary = route.get("summary", {})
        segments = route.get("segments", [])

        steps = []
        for segment in segments:
            for step in segment.get("steps", []):
                steps.append({
                    "instruction": step.get("instruction", ""),
                    "name": step.get("name", ""),
                    "distance_miles": round(step.get("distance", 0) * 0.000621371, 2),
                    "duration_seconds": step.get("duration", 0),
                    "type": step.get("type", 0),  # maneuver type
                    "exit_number": step.get("exit_number"),
                    "way_points": step.get("way_points", []),
                })

        geometry = route.get("geometry", {})

        return {
            "distance_miles": round(summary.get("distance", 0) * 0.000621371, 2),
            "duration_seconds": summary.get("duration", 0),
            "duration_formatted": self._format_duration(summary.get("duration", 0)),
            "ascent_meters": summary.get("ascent", 0),
            "descent_meters": summary.get("descent", 0),
            "steps": steps,
            "geometry": geometry,  # GeoJSON LineString
            "bbox": route.get("bbox", []),
            "warnings": route.get("warnings", []),
            "extras": route.get("extras", {}),
        }

    def _format_duration(self, seconds: float) -> str:
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        if hours > 0:
            return f"{hours}h {minutes}m"
        return f"{minutes}m"

    async def geocode(self, query: str, focus_lat: float = None, focus_lon: float = None) -> list[dict]:
        """Search for locations by name/address."""
        params = {
            "api_key": settings.ORS_API_KEY,
            "text": query,
            "size": 10,
            "layers": "address,venue,locality",
        }
        if focus_lat and focus_lon:
            params["focus.point.lat"] = focus_lat
            params["focus.point.lon"] = focus_lon

        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(self.ORS_GEOCODE_URL, params=params)
            resp.raise_for_status()
            data = resp.json()

        results = []
        for feature in data.get("features", []):
            props = feature.get("properties", {})
            coords = feature["geometry"]["coordinates"]
            results.append({
                "name": props.get("name", ""),
                "label": props.get("label", ""),
                "street": props.get("street", ""),
                "city": props.get("locality", ""),
                "state": props.get("region", ""),
                "country": props.get("country", ""),
                "lat": coords[1],
                "lon": coords[0],
                "confidence": props.get("confidence", 0),
            })
        return results


routing_service = RoutingService()
