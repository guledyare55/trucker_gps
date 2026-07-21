from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import Optional
from app.services.routing_service import routing_service

router = APIRouter(prefix="/routing", tags=["Routing"])


class TruckRouteRequest(BaseModel):
    start_lat: float = Field(..., ge=-90, le=90, description="Start latitude")
    start_lon: float = Field(..., ge=-180, le=180, description="Start longitude")
    end_lat: float = Field(..., ge=-90, le=90, description="End latitude")
    end_lon: float = Field(..., ge=-180, le=180, description="End longitude")
    height_meters: float = Field(4.11, ge=0.5, le=6.0, description="Vehicle height in meters (default 13'6\")")
    weight_kg: float = Field(36287.0, ge=100, le=100000, description="Vehicle weight in kg (default 80,000 lbs)")
    length_meters: float = Field(22.86, ge=1, le=30, description="Vehicle length in meters (default 75ft)")
    width_meters: float = Field(2.59, ge=0.5, le=4.0, description="Vehicle width in meters")
    axle_load_kg: float = Field(9000.0, ge=100, le=20000, description="Axle load in kg")
    hazmat: bool = Field(False, description="Carrying hazardous materials")
    avoid_tollways: bool = Field(False, description="Avoid toll roads")
    avoid_ferries: bool = Field(False, description="Avoid ferries")
    waypoints: Optional[list[list[float]]] = Field(None, description="Additional waypoints [[lon, lat], ...]")


class GeocodeRequest(BaseModel):
    query: str = Field(..., min_length=2, description="Address or place name to search")
    focus_lat: Optional[float] = None
    focus_lon: Optional[float] = None


@router.post("/route", summary="Calculate truck-optimized route")
async def get_truck_route(request: TruckRouteRequest):
    """
    Calculate a truck-specific route using OpenRouteService HGV profile.
    Avoids roads with height, weight, length restrictions based on truck profile.
    Returns GeoJSON geometry and turn-by-turn instructions.
    """
    avoid_features = []
    if request.avoid_tollways:
        avoid_features.append("tollways")
    if request.avoid_ferries:
        avoid_features.append("ferries")

    try:
        result = await routing_service.get_route(
            start_lon=request.start_lon,
            start_lat=request.start_lat,
            end_lon=request.end_lon,
            end_lat=request.end_lat,
            height_meters=request.height_meters,
            weight_kg=request.weight_kg,
            length_meters=request.length_meters,
            width_meters=request.width_meters,
            axle_load_kg=request.axle_load_kg,
            hazmat=request.hazmat,
            avoid_features=avoid_features if avoid_features else None,
            waypoints=request.waypoints,
        )
        if "error" in result:
            raise HTTPException(status_code=404, detail=result["error"])
        return result
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Routing error: {str(e)}")


@router.get("/geocode", summary="Search for locations by address")
async def geocode(
    q: str = Query(..., min_length=2, description="Search query"),
    lat: Optional[float] = Query(None, description="Focus latitude for nearby results"),
    lon: Optional[float] = Query(None, description="Focus longitude for nearby results"),
):
    """
    Geocode an address or place name using OpenRouteService Pelias geocoder.
    Returns list of matching locations with coordinates.
    """
    try:
        results = await routing_service.geocode(q, focus_lat=lat, focus_lon=lon)
        return {"results": results, "count": len(results)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Geocoding error: {str(e)}")


@router.get("/reverse-geocode", summary="Reverse geocode coordinates to address")
async def reverse_geocode(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
):
    """Get address from coordinates."""
    try:
        # Use Nominatim (free, OSM-based) for reverse geocoding
        import httpx
        url = "https://nominatim.openstreetmap.org/reverse"
        params = {"lat": lat, "lon": lon, "format": "jsonv2", "zoom": 18, "addressdetails": 1}
        headers = {"User-Agent": "TruckerGPS/1.0"}
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(url, params=params, headers=headers)
            data = resp.json()
        addr = data.get("address", {})
        return {
            "display_name": data.get("display_name", ""),
            "house_number": addr.get("house_number", ""),
            "road": addr.get("road", ""),
            "city": addr.get("city") or addr.get("town") or addr.get("village", ""),
            "state": addr.get("state", ""),
            "country": addr.get("country", ""),
            "postcode": addr.get("postcode", ""),
            "lat": lat,
            "lon": lon,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
