import httpx
import json
from app.core.config import settings
from app.core.database import get_redis


class POIService:
    """
    Trucker Point of Interest service using Overpass API (completely free).
    Queries OpenStreetMap for truck-relevant POI:
    - Truck stops (highway=services)
    - Weigh stations (amenity=weighbridge)
    - Rest areas (highway=rest_area)
    - Diesel fuel stations (amenity=fuel + fuel:diesel=yes)
    - Truck parking (amenity=parking + hgv=yes)
    - Truck washes
    """

    OVERPASS_URL = settings.OVERPASS_URL

    # Trucker-specific brand operators
    MAJOR_TRUCK_STOPS = [
        "Pilot Flying J", "Pilot", "Flying J",
        "Love's Travel Stop", "Love's", "Loves",
        "TravelCenters of America", "TA", "Petro Stopping Centers", "Petro",
        "Kwik Trip", "Kwik Star",
        "Sheetz", "Wawa", "Casey's",
    ]

    POI_TYPES = {
        "truck_stop": {
            "query": '["highway"="services"]',
            "icon": "local_gas_station",
            "color": "#FF6B35",
        },
        "weigh_station": {
            "query": '["amenity"="weighbridge"]',
            "icon": "monitor_weight",
            "color": "#FFD600",
        },
        "rest_area": {
            "query": '["highway"="rest_area"]',
            "icon": "local_parking",
            "color": "#00D4FF",
        },
        "fuel_diesel": {
            "query": '["amenity"="fuel"]["fuel:diesel"="yes"]',
            "icon": "local_gas_station",
            "color": "#00E676",
        },
        "truck_parking": {
            "query": '["amenity"="parking"]["hgv"="yes"]',
            "icon": "local_parking",
            "color": "#7B68EE",
        },
        "truck_wash": {
            "query": '["amenity"="car_wash"]["hgv"="yes"]',
            "icon": "local_car_wash",
            "color": "#00BCD4",
        },
        "scales": {
            "query": '["amenity"="weighbridge"]',
            "icon": "scale",
            "color": "#FF9800",
        },
    }

    async def get_pois_in_bbox(
        self,
        south: float,
        west: float,
        north: float,
        east: float,
        poi_types: list[str] = None,
    ) -> list[dict]:
        """Get all truck POI within a bounding box."""
        redis = await get_redis()
        cache_key = f"poi:{south:.3f},{west:.3f},{north:.3f},{east:.3f}:{'-'.join(sorted(poi_types or []))}"

        cached = await redis.get(cache_key)
        if cached:
            return json.loads(cached)

        # Build Overpass query
        types_to_query = poi_types or list(self.POI_TYPES.keys())
        bbox = f"{south},{west},{north},{east}"

        queries = []
        for poi_type in types_to_query:
            if poi_type in self.POI_TYPES:
                q = self.POI_TYPES[poi_type]["query"]
                queries.append(f'  node{q}({bbox});')
                queries.append(f'  way{q}({bbox});')

        overpass_query = f"""
[out:json][timeout:30];
(
{chr(10).join(queries)}
);
out center tags;
"""
        async with httpx.AsyncClient(timeout=35) as client:
            resp = await client.post(self.OVERPASS_URL, data={"data": overpass_query})
            resp.raise_for_status()
            data = resp.json()

        results = self._parse_overpass_elements(data.get("elements", []))

        await redis.setex(cache_key, settings.POI_CACHE_TTL, json.dumps(results))
        return results

    async def get_pois_along_route(
        self,
        route_coords: list[list[float]],
        radius_meters: float = 8047,  # 5 miles
        poi_types: list[str] = None,
    ) -> list[dict]:
        """Get truck POI within radius of route corridor."""
        if not route_coords:
            return []

        # Sample route every ~20 points to build bounding box
        sampled = route_coords[::max(1, len(route_coords) // 20)]

        lats = [c[1] for c in sampled]
        lons = [c[0] for c in sampled]
        
        # Expand bbox by radius
        deg_offset = radius_meters / 111000  # approx degrees
        south = min(lats) - deg_offset
        west = min(lons) - deg_offset
        north = max(lats) + deg_offset
        east = max(lons) + deg_offset

        return await self.get_pois_in_bbox(south, west, north, east, poi_types)

    async def search_truck_stops(self, query: str, lat: float, lon: float, radius_m: float = 50000) -> list[dict]:
        """Search for specific truck stop brands near location."""
        redis = await get_redis()
        cache_key = f"ts_search:{lat:.3f},{lon:.3f}:{query}:{radius_m}"

        cached = await redis.get(cache_key)
        if cached:
            return json.loads(cached)

        overpass_query = f"""
[out:json][timeout:30];
(
  node["amenity"="fuel"]["name"~"{query}",i](around:{radius_m},{lat},{lon});
  node["highway"="services"]["name"~"{query}",i](around:{radius_m},{lat},{lon});
  way["highway"="services"]["name"~"{query}",i](around:{radius_m},{lat},{lon});
);
out center tags;
"""
        async with httpx.AsyncClient(timeout=35) as client:
            resp = await client.post(self.OVERPASS_URL, data={"data": overpass_query})
            resp.raise_for_status()
            data = resp.json()

        results = self._parse_overpass_elements(data.get("elements", []))
        await redis.setex(cache_key, settings.POI_CACHE_TTL, json.dumps(results))
        return results

    def _parse_overpass_elements(self, elements: list) -> list[dict]:
        """Parse Overpass API elements into standardized POI objects."""
        pois = []
        for el in elements:
            tags = el.get("tags", {})

            # Get coordinates
            if el.get("type") == "node":
                lat = el.get("lat")
                lon = el.get("lon")
            elif el.get("center"):
                lat = el["center"]["lat"]
                lon = el["center"]["lon"]
            else:
                continue

            # Determine POI type
            poi_type = self._classify_poi(tags)

            # Parse amenities
            amenities = self._extract_amenities(tags)

            poi = {
                "id": f"{el['type']}_{el['id']}",
                "osm_id": el["id"],
                "osm_type": el["type"],
                "type": poi_type,
                "name": tags.get("name", tags.get("operator", "Unknown")),
                "lat": lat,
                "lon": lon,
                "brand": tags.get("brand", tags.get("operator", "")),
                "phone": tags.get("phone", tags.get("contact:phone", "")),
                "website": tags.get("website", tags.get("contact:website", "")),
                "opening_hours": tags.get("opening_hours", ""),
                "address": {
                    "street": tags.get("addr:street", ""),
                    "city": tags.get("addr:city", ""),
                    "state": tags.get("addr:state", ""),
                    "zip": tags.get("addr:postcode", ""),
                },
                "amenities": amenities,
                "fuel": {
                    "diesel": tags.get("fuel:diesel") in ("yes", "1"),
                    "def": tags.get("fuel:HGV_diesel") in ("yes", "1"),
                    "adblue": tags.get("fuel:adblue") in ("yes", "1"),
                },
                "truck": {
                    "parking": tags.get("parking") or tags.get("hgv") == "yes",
                    "truck_lanes": tags.get("hgv") == "yes",
                    "max_height": tags.get("maxheight"),
                    "max_weight": tags.get("maxweight"),
                },
                "icon": self.POI_TYPES.get(poi_type, {}).get("icon", "place"),
                "color": self.POI_TYPES.get(poi_type, {}).get("color", "#666666"),
            }
            pois.append(poi)
        return pois

    def _classify_poi(self, tags: dict) -> str:
        amenity = tags.get("amenity", "")
        highway = tags.get("highway", "")
        if highway == "services":
            return "truck_stop"
        if highway == "rest_area":
            return "rest_area"
        if amenity == "weighbridge":
            return "weigh_station"
        if amenity == "fuel":
            return "fuel_diesel"
        if amenity == "parking":
            return "truck_parking"
        if amenity == "car_wash":
            return "truck_wash"
        return "truck_stop"

    def _extract_amenities(self, tags: dict) -> list[str]:
        amenities = []
        mapping = {
            "shower": ["shower", "amenity:shower"],
            "restaurant": ["amenity:restaurant", "restaurant"],
            "wifi": ["internet_access", "wifi"],
            "atm": ["atm"],
            "laundry": ["laundry"],
            "scale": ["amenity:weighbridge", "scale"],
            "repair": ["amenity:car_repair", "repair"],
            "parking": ["parking", "hgv"],
        }
        for label, tag_keys in mapping.items():
            for key in tag_keys:
                if tags.get(key) in ("yes", "1", "indoor", "outdoor"):
                    amenities.append(label)
                    break
        return amenities


poi_service = POIService()
