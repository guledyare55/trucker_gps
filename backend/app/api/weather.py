from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from app.services.weather_service import weather_service

router = APIRouter(prefix="/weather", tags=["Weather"])


@router.get("/current", summary="Get current weather at location")
async def get_current_weather(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
):
    """
    Get current weather conditions at a location.
    Includes truck-specific alerts (wind, ice, fog warnings).
    Uses Open-Meteo API (completely free, no API key needed).
    """
    try:
        return await weather_service.get_current_weather(lat, lon)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class RouteWeatherRequest(BaseModel):
    route_coords: list[list[float]]  # [[lon, lat], ...]
    departure_time: Optional[str] = None


@router.post("/route", summary="Get weather along a route")
async def get_route_weather(request: RouteWeatherRequest):
    """
    Get weather conditions at multiple points along a planned route.
    Samples up to 10 points. Includes truck weather alerts.
    """
    if len(request.route_coords) < 2:
        raise HTTPException(status_code=400, detail="Route needs at least 2 coordinates")
    try:
        points = await weather_service.get_route_weather(
            request.route_coords, request.departure_time
        )
        return {"weather_points": points, "count": len(points)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/alerts", summary="Get NOAA severe weather alerts (US only)")
async def get_weather_alerts(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
):
    """
    Get active NOAA severe weather alerts for US location.
    Returns truck-relevant alerts (wind, ice, snow, flood, etc.).
    Completely free - no API key needed.
    """
    try:
        alerts = await weather_service.get_severe_alerts_us(lat, lon)
        return {"alerts": alerts, "count": len(alerts)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/tile-urls", summary="Get weather tile layer URLs for map overlay")
async def get_weather_tile_urls():
    """
    Get OpenWeatherMap tile URLs for map overlay layers.
    Requires OWM_API_KEY in backend config.
    Returns URLs for: precipitation, wind, temperature, clouds, pressure.
    """
    urls = weather_service.get_weather_tile_urls()
    if not urls:
        return {
            "message": "Configure OWM_API_KEY in .env for weather tile overlays",
            "tile_urls": {},
        }
    return {"tile_urls": urls}
