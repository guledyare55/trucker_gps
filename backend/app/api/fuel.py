from fastapi import APIRouter, HTTPException, Query
from app.services.fuel_service import fuel_service

router = APIRouter(prefix="/fuel", tags=["Fuel"])


@router.get("/prices", summary="Get US regional diesel prices")
async def get_diesel_prices():
    """
    Get current US regional diesel prices from EIA (US Energy Information Administration).
    Cached for 1 hour. Falls back to estimated prices if EIA_API_KEY not configured.
    """
    try:
        return await fuel_service.get_diesel_prices()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/estimate", summary="Estimate trip fuel cost")
async def estimate_fuel_cost(
    distance_miles: float = Query(..., gt=0, description="Trip distance in miles"),
    mpg: float = Query(6.5, gt=0, le=50, description="Fuel efficiency in MPG (default 6.5 for loaded semi)"),
    region: str = Query("us_avg", description="US region: us_avg, east_coast, midwest, gulf_coast, rocky_mountain, west_coast, california"),
):
    """
    Estimate fuel cost for a trip based on distance, efficiency, and regional diesel prices.
    Calculates number of fuel stops needed based on 100-gallon tank.
    """
    valid_regions = ["us_avg", "east_coast", "midwest", "gulf_coast", "rocky_mountain", "west_coast", "california"]
    if region not in valid_regions:
        raise HTTPException(status_code=400, detail=f"Invalid region. Valid: {', '.join(valid_regions)}")

    try:
        return await fuel_service.estimate_trip_fuel_cost(distance_miles, mpg, region)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
