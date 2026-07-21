from fastapi import APIRouter, HTTPException, Depends, Query
from pydantic import BaseModel
from typing import Optional
from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from app.core.database import get_db
from app.models.models import HOSLog, DutyStatus
from app.services.hos_service import hos_service
import uuid

router = APIRouter(prefix="/hos", tags=["Hours of Service / ELD"])


class DutyStatusUpdate(BaseModel):
    user_id: str
    duty_status: DutyStatus
    location_name: Optional[str] = None
    notes: Optional[str] = None


class HOSLogCreate(BaseModel):
    user_id: str
    duty_status: DutyStatus
    start_time: datetime
    end_time: Optional[datetime] = None
    location_name: Optional[str] = None
    odometer_start: Optional[float] = None
    odometer_end: Optional[float] = None
    notes: Optional[str] = None


def _serialize_log(log: HOSLog) -> dict:
    return {
        "id": log.id,
        "user_id": log.user_id,
        "duty_status": log.duty_status,
        "start_time": log.start_time.isoformat() if log.start_time else None,
        "end_time": log.end_time.isoformat() if log.end_time else None,
        "location_name": log.location_name,
        "odometer_start": log.odometer_start,
        "odometer_end": log.odometer_end,
        "notes": log.notes,
    }


@router.get("/summary/{user_id}", summary="Get HOS compliance summary")
async def get_hos_summary(
    user_id: str,
    db: AsyncSession = Depends(get_db),
):
    """
    Calculate current HOS status for a driver.
    Returns remaining drive time, duty window, violations, and break requirements.
    Fully compliant with FMCSA 49 CFR Part 395.
    """
    # Get last 8 days of logs
    from datetime import timedelta
    window_start = datetime.now(timezone.utc) - timedelta(days=8)

    result = await db.execute(
        select(HOSLog)
        .where(HOSLog.user_id == user_id)
        .where(HOSLog.start_time >= window_start)
        .order_by(HOSLog.start_time)
    )
    logs = result.scalars().all()

    # Convert to dict format for service
    log_dicts = []
    for log in logs:
        log_dicts.append({
            "duty_status": log.duty_status,
            "start_time": log.start_time,
            "end_time": log.end_time,
        })

    return hos_service.calculate_hos_summary(log_dicts)


@router.post("/status", summary="Update driver duty status")
async def update_duty_status(
    update: DutyStatusUpdate,
    db: AsyncSession = Depends(get_db),
):
    """
    Update driver's current duty status (Off Duty, Sleeper Berth, Driving, On Duty).
    Closes the previous log entry and creates a new one.
    """
    now = datetime.now(timezone.utc)

    # Close previous open log
    result = await db.execute(
        select(HOSLog)
        .where(HOSLog.user_id == update.user_id)
        .where(HOSLog.end_time == None)
        .order_by(desc(HOSLog.start_time))
    )
    prev_log = result.scalar_one_or_none()
    if prev_log:
        prev_log.end_time = now
        db.add(prev_log)

    # Create new log entry
    new_log = HOSLog(
        id=str(uuid.uuid4()),
        user_id=update.user_id,
        duty_status=update.duty_status,
        start_time=now,
        location_name=update.location_name,
        notes=update.notes,
    )
    db.add(new_log)
    await db.flush()

    return {
        "message": f"Status updated to {update.duty_status.value}",
        "log_id": new_log.id,
        "started_at": now.isoformat(),
    }


@router.get("/logs/{user_id}", summary="Get driver HOS logs")
async def get_hos_logs(
    user_id: str,
    days: int = Query(7, ge=1, le=30),
    db: AsyncSession = Depends(get_db),
):
    """Get HOS log entries for a driver (default last 7 days)."""
    from datetime import timedelta
    window_start = datetime.now(timezone.utc) - timedelta(days=days)

    result = await db.execute(
        select(HOSLog)
        .where(HOSLog.user_id == user_id)
        .where(HOSLog.start_time >= window_start)
        .order_by(desc(HOSLog.start_time))
    )
    logs = result.scalars().all()

    return {
        "logs": [_serialize_log(log) for log in logs],
        "count": len(logs),
        "days": days,
    }


@router.post("/logs", summary="Manually create HOS log entry")
async def create_hos_log(
    log_data: HOSLogCreate,
    db: AsyncSession = Depends(get_db),
):
    """Manually add a HOS log entry (for corrections or retroactive logging)."""
    log = HOSLog(
        id=str(uuid.uuid4()),
        user_id=log_data.user_id,
        duty_status=log_data.duty_status,
        start_time=log_data.start_time,
        end_time=log_data.end_time,
        location_name=log_data.location_name,
        odometer_start=log_data.odometer_start,
        odometer_end=log_data.odometer_end,
        notes=log_data.notes,
    )
    db.add(log)
    await db.flush()
    return _serialize_log(log)


@router.get("/violations/{user_id}", summary="Check for HOS violations")
async def check_violations(
    user_id: str,
    db: AsyncSession = Depends(get_db),
):
    """Check for current HOS violations and warnings for a driver."""
    summary = await get_hos_summary(user_id, db)
    return {
        "violations": summary.get("violations", []),
        "has_violations": len(summary.get("violations", [])) > 0,
        "break_required": summary.get("break_required", False),
        "driving_hours_remaining": summary.get("driving_hours_remaining", 0),
    }
