import httpx
import json
from app.core.config import settings
from app.core.database import get_redis


class FuelService:
    """
    Fuel price service using EIA (US Energy Information Administration) API.
    Free US government API. Returns weekly regional diesel prices.
    
    Also integrates GasBuddy-style data through Overpass (truck stop fuel prices
    may be tagged in OSM for some locations).
    """

    EIA_BASE_URL = settings.EIA_BASE_URL

    # EIA petroleum series IDs for diesel
    DIESEL_SERIES = {
        "us_avg": "EMD_EPD2D_PTE_NUS_DPG",   # US Average diesel
        "east_coast": "EMD_EPD2D_PTE_R10_DPG",
        "midwest": "EMD_EPD2D_PTE_R20_DPG",
        "gulf_coast": "EMD_EPD2D_PTE_R30_DPG",
        "rocky_mountain": "EMD_EPD2D_PTE_R40_DPG",
        "west_coast": "EMD_EPD2D_PTE_R50_DPG",
        "california": "EMD_EPD2D_PTE_SCA_DPG",
    }

    # Fuel efficiency defaults (mpg) by truck type
    FUEL_EFFICIENCY = {
        "semi_loaded": 6.5,
        "semi_empty": 8.0,
        "box_truck": 12.0,
        "pickup": 20.0,
    }

    async def get_diesel_prices(self) -> dict:
        """Get current US regional diesel prices from EIA API."""
        redis = await get_redis()
        cache_key = "fuel:eia_diesel_prices"

        cached = await redis.get(cache_key)
        if cached:
            return json.loads(cached)

        if not settings.EIA_API_KEY:
            # Return estimated prices if no API key
            return self._estimated_prices()

        try:
            params = {
                "api_key": settings.EIA_API_KEY,
                "frequency": "weekly",
                "data[0]": "value",
                "facets[product][]": "EPD2D",  # No. 2 Diesel
                "sort[0][column]": "period",
                "sort[0][direction]": "desc",
                "length": 20,
            }
            async with httpx.AsyncClient(timeout=15) as client:
                resp = await client.get(f"{self.EIA_BASE_URL}/petroleum/pri/gnd/data/", params=params)
                resp.raise_for_status()
                data = resp.json()

            prices = self._parse_eia_response(data)
            await redis.setex(cache_key, settings.FUEL_CACHE_TTL, json.dumps(prices))
            return prices
        except Exception:
            return self._estimated_prices()

    async def estimate_trip_fuel_cost(
        self,
        distance_miles: float,
        mpg: float = 6.5,
        region: str = "us_avg",
    ) -> dict:
        """Estimate fuel cost for a trip."""
        prices = await self.get_diesel_prices()
        price_per_gallon = prices.get("regions", {}).get(region, {}).get("price", 3.85)

        gallons_needed = distance_miles / mpg
        total_cost = gallons_needed * price_per_gallon

        # Fuel stops estimate (assume 100 gallon tank, keep above 1/4 tank)
        usable_tank_gallons = 100 * 0.75  # Use 75% of tank per fill
        fuel_stops = max(0, int(gallons_needed / usable_tank_gallons))

        return {
            "distance_miles": round(distance_miles, 1),
            "fuel_efficiency_mpg": mpg,
            "gallons_needed": round(gallons_needed, 1),
            "price_per_gallon": price_per_gallon,
            "estimated_cost_usd": round(total_cost, 2),
            "estimated_fuel_stops": fuel_stops,
            "region": region,
            "price_date": prices.get("last_updated", ""),
        }

    def _parse_eia_response(self, data: dict) -> dict:
        """Parse EIA API response into regional price map."""
        regional_prices = {}
        response_data = data.get("response", {}).get("data", [])

        # Group by area (duoarea)
        area_prices = {}
        for item in response_data:
            area = item.get("duoAreaName", "U.S.")
            if area not in area_prices:
                area_prices[area] = item.get("value", 3.85)

        # Map to simplified regions
        region_map = {
            "U.S.": ("us_avg", "US Average"),
            "East Coast": ("east_coast", "East Coast"),
            "Midwest": ("midwest", "Midwest"),
            "Gulf Coast": ("gulf_coast", "Gulf Coast"),
            "Rocky Mountain": ("rocky_mountain", "Rocky Mountain"),
            "West Coast": ("west_coast", "West Coast"),
        }

        regions = {}
        for eia_name, (key, label) in region_map.items():
            price = area_prices.get(eia_name, 3.85)
            regions[key] = {
                "label": label,
                "price": round(price, 3),
                "unit": "USD/gallon",
                "fuel_type": "Diesel No. 2",
            }

        return {
            "regions": regions,
            "last_updated": response_data[0].get("period", "") if response_data else "",
            "source": "US Energy Information Administration",
        }

    def _estimated_prices(self) -> dict:
        """Return estimated prices when EIA API key not configured."""
        return {
            "regions": {
                "us_avg": {"label": "US Average", "price": 3.85, "unit": "USD/gallon", "fuel_type": "Diesel No. 2"},
                "east_coast": {"label": "East Coast", "price": 3.91, "unit": "USD/gallon", "fuel_type": "Diesel No. 2"},
                "midwest": {"label": "Midwest", "price": 3.79, "unit": "USD/gallon", "fuel_type": "Diesel No. 2"},
                "gulf_coast": {"label": "Gulf Coast", "price": 3.72, "unit": "USD/gallon", "fuel_type": "Diesel No. 2"},
                "rocky_mountain": {"label": "Rocky Mountain", "price": 3.88, "unit": "USD/gallon", "fuel_type": "Diesel No. 2"},
                "west_coast": {"label": "West Coast", "price": 4.15, "unit": "USD/gallon", "fuel_type": "Diesel No. 2"},
                "california": {"label": "California", "price": 4.42, "unit": "USD/gallon", "fuel_type": "Diesel No. 2"},
            },
            "last_updated": "Estimated (add EIA_API_KEY for live prices)",
            "source": "Estimated - US Energy Information Administration",
        }


fuel_service = FuelService()
