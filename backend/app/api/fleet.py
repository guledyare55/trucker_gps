from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect, Query, Depends
from pydantic import BaseModel
from typing import Optional
from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, update
from app.core.database import get_db, get_redis
from app.models.models import User, Trip, TruckLocation
import uuid
import json

router = APIRouter(prefix="/fleet", tags=["Fleet Management"])


# ─── WebSocket connection manager ──────────────────────────────────────────────

class FleetConnectionManager:
    def __init__(self):
        self.active_connections: dict[str, WebSocket] = {}

    async def connect(self, driver_id: str, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[driver_id] = websocket

    def disconnect(self, driver_id: str):
        self.active_connections.pop(driver_id, None)

    async def send_location_update(self, driver_id: str, data: dict):
        ws = self.active_connections.get(driver_id)
        if ws:
            try:
                await ws.send_json(data)
            except Exception:
                self.disconnect(driver_id)

    async def broadcast_to_fleet(self, fleet_id: str, data: dict):
        """Send update to all connected fleet members."""
        for driver_id, ws in list(self.active_connections.items()):
            try:
                await ws.send_json(data)
            except Exception:
                self.disconnect(driver_id)

    @property
    def connected_count(self):
        return len(self.active_connections)


manager = FleetConnectionManager()


# ─── Models ────────────────────────────────────────────────────────────────────

class LocationUpdate(BaseModel):
    user_id: str
    lat: float
    lon: float
    speed_mph: float = 0.0
    heading_degrees: float = 0.0
    altitude_meters: float = 0.0
    accuracy_meters: float = 0.0


class TripCreate(BaseModel):
    user_id: str
    truck_profile_id: Optional[str] = None
    origin_name: str
    destination_name: str
    origin_lat: float
    origin_lon: float
    destination_lat: float
    destination_lon: float
    distance_miles: Optional[float] = None
    duration_hours: Optional[float] = None


# ─── WebSocket Endpoints ────────────────────────────────────────────────────────

@router.websocket("/ws/driver/{driver_id}")
async def driver_location_stream(websocket: WebSocket, driver_id: str):
    """
    WebSocket endpoint for real-time driver location streaming.
    Drivers connect here to broadcast their GPS position.
    Fleet managers receive updates via /ws/fleet/{fleet_id}.
    
    Message format: {"lat": float, "lon": float, "speed_mph": float, "heading": float}
    """
    await manager.connect(driver_id, websocket)
    redis = await get_redis()

    try:
        while True:
            data = await websocket.receive_json()
            # Store latest position in Redis for fleet manager queries
            location_data = {
                "driver_id": driver_id,
                "lat": data.get("lat"),
                "lon": data.get("lon"),
                "speed_mph": data.get("speed_mph", 0),
                "heading": data.get("heading", 0),
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
            await redis.setex(
                f"driver_location:{driver_id}",
                300,  # Expire after 5 minutes if no update
                json.dumps(location_data),
            )
            # Publish to fleet channel
            await redis.publish(f"fleet_updates", json.dumps(location_data))

    except WebSocketDisconnect:
        manager.disconnect(driver_id)
        await redis.delete(f"driver_location:{driver_id}")


# ─── REST Endpoints ────────────────────────────────────────────────────────────

@router.get("/drivers/live", summary="Get all active driver locations")
async def get_active_drivers():
    """Get real-time locations of all currently active drivers."""
    redis = await get_redis()
    driver_keys = await redis.keys("driver_location:*")

    locations = []
    for key in driver_keys:
        data = await redis.get(key)
        if data:
            locations.append(json.loads(data))

    return {
        "active_drivers": locations,
        "count": len(locations),
        "connected_websockets": manager.connected_count,
    }


@router.post("/location", summary="Update driver location (REST fallback)")
async def update_driver_location(
    update: LocationUpdate,
    db: AsyncSession = Depends(get_db),
):
    """REST fallback for location updates when WebSocket not available."""
    from geoalchemy2 import WKTElement
    location = TruckLocation(
        id=str(uuid.uuid4()),
        user_id=update.user_id,
        location=WKTElement(f"POINT({update.lon} {update.lat})", srid=4326),
        speed_mph=update.speed_mph,
        heading_degrees=update.heading_degrees,
        altitude_meters=update.altitude_meters,
        accuracy_meters=update.accuracy_meters,
    )
    db.add(location)
    await db.flush()
    return {"status": "ok", "location_id": location.id}


@router.get("/location/history/{user_id}", summary="Get driver location history")
async def get_location_history(
    user_id: str,
    hours: int = Query(24, ge=1, le=168),
    db: AsyncSession = Depends(get_db),
):
    """Get a driver's location history for the past N hours."""
    from datetime import timedelta
    window_start = datetime.now(timezone.utc) - timedelta(hours=hours)

    result = await db.execute(
        select(TruckLocation)
        .where(TruckLocation.user_id == user_id)
        .where(TruckLocation.recorded_at >= window_start)
        .order_by(TruckLocation.recorded_at)
    )
    locations = result.scalars().all()

    return {
        "user_id": user_id,
        "hours": hours,
        "points": [
            {
                "lat": loc.location.desc if hasattr(loc.location, 'desc') else None,
                "lon": None,
                "speed_mph": loc.speed_mph,
                "heading": loc.heading_degrees,
                "timestamp": loc.recorded_at.isoformat(),
            }
            for loc in locations
        ],
        "count": len(locations),
    }


# ─── Trip Management ────────────────────────────────────────────────────────────

@router.post("/trips", summary="Create a new trip")
async def create_trip(
    trip_data: TripCreate,
    db: AsyncSession = Depends(get_db),
):
    """Create a new planned or active trip."""
    trip = Trip(
        id=str(uuid.uuid4()),
        **trip_data.model_dump(),
        status="planned",
    )
    db.add(trip)
    await db.flush()
    return {"trip_id": trip.id, "status": "planned"}


@router.get("/trips/{user_id}", summary="Get trip history")
async def get_trips(
    user_id: str,
    status: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
):
    """Get trip history for a driver."""
    query = select(Trip).where(Trip.user_id == user_id).order_by(desc(Trip.created_at)).limit(limit)
    if status:
        query = query.where(Trip.status == status)

    result = await db.execute(query)
    trips = result.scalars().all()

    return {
        "trips": [
            {
                "id": t.id,
                "origin": t.origin_name,
                "destination": t.destination_name,
                "distance_miles": t.distance_miles,
                "duration_hours": t.duration_hours,
                "status": t.status,
                "started_at": t.started_at.isoformat() if t.started_at else None,
                "completed_at": t.completed_at.isoformat() if t.completed_at else None,
            }
            for t in trips
        ],
        "count": len(trips),
    }


@router.put("/trips/{trip_id}/status", summary="Update trip status")
async def update_trip_status(
    trip_id: str,
    status: str = Query(..., description="new_status: planned, active, completed, cancelled"),
    db: AsyncSession = Depends(get_db),
):
    """Update the status of a trip."""
    valid_statuses = ["planned", "active", "completed", "cancelled"]
    if status not in valid_statuses:
        raise HTTPException(status_code=400, detail=f"Invalid status. Valid: {valid_statuses}")

    now = datetime.now(timezone.utc)
    update_data = {"status": status}
    if status == "active":
        update_data["started_at"] = now
    elif status in ("completed", "cancelled"):
        update_data["completed_at"] = now

    await db.execute(
        update(Trip).where(Trip.id == trip_id).values(**update_data)
    )
    return {"trip_id": trip_id, "status": status, "updated_at": now.isoformat()}


@router.get("/share/{driver_id}", summary="Get public shareable driver location")
async def get_shareable_location(driver_id: str):
    """
    Get a driver's current location for sharing with dispatchers or customers.
    Returns a sanitized location object (no personal data).
    """
    redis = await get_redis()
    data = await redis.get(f"driver_location:{driver_id}")
    if not data:
        raise HTTPException(status_code=404, detail="Driver not currently active or location expired")

    location = json.loads(data)
    return {
        "driver_id": driver_id,
        "lat": location.get("lat"),
        "lon": location.get("lon"),
        "speed_mph": location.get("speed_mph"),
        "last_updated": location.get("timestamp"),
        "share_url": f"/fleet/share/{driver_id}",
    }
