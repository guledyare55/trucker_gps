from fastapi import APIRouter, HTTPException, Query
from typing import Optional
from app.services.poi_service import poi_service

router = APIRouter(prefix="/poi", tags=["Points of Interest"])

VALID_POI_TYPES = [
    "truck_stop", "weigh_station", "rest_area",
    "fuel_diesel", "truck_parking", "truck_wash", "scales"
]


@router.get("/bbox", summary="Get truck POI within bounding box")
async def get_pois_in_bbox(
    south: float = Query(..., ge=-90, le=90),
    west: float = Query(..., ge=-180, le=180),
    north: float = Query(..., ge=-90, le=90),
    east: float = Query(..., ge=-180, le=180),
    types: Optional[str] = Query(
        None,
        description="Comma-separated POI types: truck_stop,weigh_station,rest_area,fuel_diesel,truck_parking"
    ),
):
    """
    Get all truck-specific POI within a map bounding box.
    Uses OpenStreetMap Overpass API (free).
    Results cached for 24 hours.
    """
    # Validate bbox size (prevent huge queries)
    lat_span = abs(north - south)
    lon_span = abs(east - west)
    if lat_span > 5 or lon_span > 5:
        raise HTTPException(status_code=400, detail="Bounding box too large. Max 5 degrees span.")

    poi_types = None
    if types:
        poi_types = [t.strip() for t in types.split(",") if t.strip() in VALID_POI_TYPES]

    try:
        pois = await poi_service.get_pois_in_bbox(south, west, north, east, poi_types)
        return {
            "pois": pois,
            "count": len(pois),
            "bbox": {"south": south, "west": west, "north": north, "east": east},
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/along-route", summary="Get truck POI along a route corridor")
async def get_pois_along_route(
    route_coords: list[list[float]],
    radius_miles: float = Query(5.0, ge=0.5, le=25.0),
    types: Optional[str] = Query(None),
):
    """
    Get truck POI within a radius of a route.
    route_coords: List of [lon, lat] coordinate pairs forming the route.
    """
    if len(route_coords) < 2:
        raise HTTPException(status_code=400, detail="Route must have at least 2 coordinates")

    poi_types = None
    if types:
        poi_types = [t.strip() for t in types.split(",") if t.strip() in VALID_POI_TYPES]

    radius_meters = radius_miles * 1609.34
    try:
        pois = await poi_service.get_pois_along_route(route_coords, radius_meters, poi_types)
        return {"pois": pois, "count": len(pois), "radius_miles": radius_miles}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/search", summary="Search for truck stops by name/brand")
async def search_truck_stops(
    q: str = Query(..., min_length=2, description="Search query (e.g. 'Pilot', 'Flying J', 'Love's')"),
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    radius_miles: float = Query(50.0, ge=1.0, le=200.0),
):
    """Search for specific truck stop brands near a location."""
    radius_meters = radius_miles * 1609.34
    try:
        results = await poi_service.search_truck_stops(q, lat, lon, radius_meters)
        return {"results": results, "count": len(results)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/nearby", summary="Get nearest truck POI to a location")
async def get_nearby_pois(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    radius_miles: float = Query(25.0, ge=1.0, le=100.0),
    type: Optional[str] = Query("truck_stop", description="Single POI type to search"),
    limit: int = Query(20, ge=1, le=100),
):
    """Get nearest truck POI to current location."""
    radius_meters = radius_miles * 1609.34
    deg_offset = radius_meters / 111000
    poi_types = [type] if type in VALID_POI_TYPES else None

    try:
        pois = await poi_service.get_pois_in_bbox(
            south=lat - deg_offset,
            west=lon - deg_offset,
            north=lat + deg_offset,
            east=lon + deg_offset,
            poi_types=poi_types,
        )
        # Sort by distance from current location
        import math
        def distance(poi):
            dlat = poi["lat"] - lat
            dlon = poi["lon"] - lon
            return math.sqrt(dlat**2 + dlon**2)

        pois.sort(key=distance)
        return {"pois": pois[:limit], "count": min(len(pois), limit)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
