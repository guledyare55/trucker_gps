import httpx
import json
from typing import Optional
from app.core.config import settings
from app.core.database import get_redis


class WeatherService:
    """
    Weather service using Open-Meteo (completely free, no API key needed).
    Also uses NOAA NWS for US severe weather alerts (completely free).
    OpenWeatherMap tile URLs for map overlay (free tier, requires OWM key).
    """

    OPEN_METEO_URL = settings.OPEN_METEO_URL
    NOAA_ALERTS_URL = "https://api.weather.gov/alerts/active"
    OWM_TILE_BASE = "https://tile.openweathermap.org/map"

    # Wind speed thresholds for trucks (mph)
    WIND_WARNING_MPH = 30
    WIND_DANGER_MPH = 45

    async def get_current_weather(self, lat: float, lon: float) -> dict:
        """Get current weather conditions at a location."""
        redis = await get_redis()
        cache_key = f"weather:current:{lat:.2f},{lon:.2f}"

        cached = await redis.get(cache_key)
        if cached:
            return json.loads(cached)

        params = {
            "latitude": lat,
            "longitude": lon,
            "current": [
                "temperature_2m",
                "apparent_temperature",
                "weather_code",
                "wind_speed_10m",
                "wind_direction_10m",
                "wind_gusts_10m",
                "precipitation",
                "snowfall",
                "visibility",
                "relative_humidity_2m",
            ],
            "wind_speed_unit": "mph",
            "temperature_unit": "fahrenheit",
            "precipitation_unit": "inch",
            "timezone": "auto",
        }

        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(f"{self.OPEN_METEO_URL}/forecast", params=params)
            resp.raise_for_status()
            data = resp.json()

        current = data.get("current", {})
        result = {
            "lat": lat,
            "lon": lon,
            "temperature_f": current.get("temperature_2m"),
            "feels_like_f": current.get("apparent_temperature"),
            "weather_code": current.get("weather_code"),
            "weather_description": self._wmo_code_to_description(current.get("weather_code", 0)),
            "wind_speed_mph": current.get("wind_speed_10m"),
            "wind_gust_mph": current.get("wind_gusts_10m"),
            "wind_direction": current.get("wind_direction_10m"),
            "wind_direction_text": self._degrees_to_cardinal(current.get("wind_direction_10m", 0)),
            "precipitation_inch": current.get("precipitation"),
            "snowfall_inch": current.get("snowfall"),
            "visibility_miles": self._km_to_miles(current.get("visibility", 0)) if current.get("visibility") else None,
            "humidity_percent": current.get("relative_humidity_2m"),
            "truck_alerts": self._generate_truck_alerts(current),
            "time": current.get("time"),
        }

        await redis.setex(cache_key, settings.WEATHER_CACHE_TTL, json.dumps(result))
        return result

    async def get_route_weather(
        self,
        route_coords: list[list[float]],
        departure_time: Optional[str] = None,
    ) -> list[dict]:
        """Get weather forecast along route at estimated arrival times."""
        if not route_coords:
            return []

        # Sample up to 10 points along route
        step = max(1, len(route_coords) // 10)
        sampled = route_coords[::step]

        weather_points = []
        for i, coord in enumerate(sampled):
            try:
                w = await self.get_current_weather(coord[1], coord[0])
                w["route_index"] = i
                w["route_position_percent"] = int(i / len(sampled) * 100)
                weather_points.append(w)
            except Exception:
                continue

        return weather_points

    async def get_severe_alerts_us(self, lat: float, lon: float) -> list[dict]:
        """Get NOAA severe weather alerts for US location (completely free)."""
        redis = await get_redis()
        cache_key = f"noaa_alerts:{lat:.2f},{lon:.2f}"

        cached = await redis.get(cache_key)
        if cached:
            return json.loads(cached)

        try:
            params = {"point": f"{lat},{lon}", "status": "actual", "message_type": "alert"}
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.get(
                    self.NOAA_ALERTS_URL,
                    params=params,
                    headers={"User-Agent": "TruckerGPS/1.0 (contact@truckergps.app)"},
                )
                resp.raise_for_status()
                data = resp.json()

            alerts = []
            for feature in data.get("features", [])[:10]:
                props = feature.get("properties", {})
                alerts.append({
                    "id": props.get("id", ""),
                    "event": props.get("event", ""),
                    "headline": props.get("headline", ""),
                    "description": props.get("description", "")[:500],
                    "severity": props.get("severity", ""),
                    "urgency": props.get("urgency", ""),
                    "onset": props.get("onset", ""),
                    "expires": props.get("expires", ""),
                    "area": props.get("areaDesc", ""),
                    "is_truck_relevant": self._is_truck_relevant_alert(props.get("event", "")),
                })

            await redis.setex(cache_key, 300, json.dumps(alerts))  # 5 min cache
            return alerts
        except Exception:
            return []

    def get_weather_tile_urls(self) -> dict[str, str]:
        """Return OpenWeatherMap tile layer URLs for map overlay."""
        if not settings.OWM_API_KEY:
            return {}
        base = f"{self.OWM_TILE_BASE}"
        key = settings.OWM_API_KEY
        return {
            "precipitation": f"{base}/precipitation_new/{{z}}/{{x}}/{{y}}.png?appid={key}",
            "wind": f"{base}/wind_new/{{z}}/{{x}}/{{y}}.png?appid={key}",
            "temperature": f"{base}/temp_new/{{z}}/{{x}}/{{y}}.png?appid={key}",
            "clouds": f"{base}/clouds_new/{{z}}/{{x}}/{{y}}.png?appid={key}",
            "pressure": f"{base}/pressure_new/{{z}}/{{x}}/{{y}}.png?appid={key}",
        }

    def _generate_truck_alerts(self, current: dict) -> list[dict]:
        """Generate truck-specific weather alerts based on conditions."""
        alerts = []
        wind = current.get("wind_speed_10m", 0)
        gust = current.get("wind_gusts_10m", 0)
        code = current.get("weather_code", 0)
        visibility = current.get("visibility", 10000)

        if gust >= self.WIND_DANGER_MPH:
            alerts.append({
                "type": "WIND_DANGER",
                "severity": "high",
                "message": f"Dangerous crosswinds: {gust:.0f} mph gusts. High-profile vehicle rollover risk.",
                "icon": "air",
            })
        elif wind >= self.WIND_WARNING_MPH:
            alerts.append({
                "type": "WIND_WARNING",
                "severity": "medium",
                "message": f"Strong winds: {wind:.0f} mph. Use caution on bridges and overpasses.",
                "icon": "air",
            })

        # Snow/ice
        if code in range(71, 78) or code in range(85, 87):
            alerts.append({
                "type": "SNOW_ICE",
                "severity": "high",
                "message": "Snow/ice conditions. Reduce speed and increase following distance.",
                "icon": "ac_unit",
            })

        # Heavy rain
        if code in range(63, 68) or code in range(81, 83):
            alerts.append({
                "type": "HEAVY_RAIN",
                "severity": "medium",
                "message": "Heavy rain. Reduced stopping distance and visibility.",
                "icon": "water_drop",
            })

        # Fog
        if code in (45, 48) or (visibility and visibility < 1000):
            alerts.append({
                "type": "FOG",
                "severity": "high",
                "message": "Fog conditions. Reduce speed and use fog lights.",
                "icon": "foggy",
            })

        return alerts

    def _is_truck_relevant_alert(self, event: str) -> bool:
        truck_keywords = [
            "Wind", "Blizzard", "Snow", "Ice", "Fog", "Freezing",
            "Winter", "Flood", "Tornado", "Hurricane", "Dust Storm",
        ]
        return any(kw.lower() in event.lower() for kw in truck_keywords)

    def _wmo_code_to_description(self, code: int) -> str:
        codes = {
            0: "Clear sky", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
            45: "Foggy", 48: "Depositing rime fog",
            51: "Light drizzle", 53: "Moderate drizzle", 55: "Dense drizzle",
            61: "Slight rain", 63: "Moderate rain", 65: "Heavy rain",
            71: "Slight snow", 73: "Moderate snow", 75: "Heavy snow",
            77: "Snow grains", 80: "Slight showers", 81: "Moderate showers", 82: "Violent showers",
            85: "Slight snow showers", 86: "Heavy snow showers",
            95: "Thunderstorm", 96: "Thunderstorm w/ hail", 99: "Thunderstorm w/ heavy hail",
        }
        return codes.get(code, "Unknown")

    def _degrees_to_cardinal(self, degrees: float) -> str:
        directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        idx = round(degrees / 22.5) % 16
        return directions[idx]

    def _km_to_miles(self, km: float) -> float:
        return round(km * 0.621371, 1)


weather_service = WeatherService()
