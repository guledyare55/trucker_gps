from sqlalchemy import Column, String, Float, Boolean, Integer, DateTime, Text, Enum as SAEnum
from sqlalchemy.sql import func
from geoalchemy2 import Geometry
from app.core.database import Base
import enum
import uuid


def gen_uuid():
    return str(uuid.uuid4())


class HazmatClass(str, enum.Enum):
    NONE = "none"
    EXPLOSIVE = "explosive"
    GAS = "gas"
    FLAMMABLE = "flammable"
    FLAMMABLE_SOLID = "flammable_solid"
    OXIDIZER = "oxidizer"
    POISON = "poison"
    RADIOACTIVE = "radioactive"
    CORROSIVE = "corrosive"
    MISC = "misc"


class DutyStatus(str, enum.Enum):
    OFF_DUTY = "off_duty"
    SLEEPER_BERTH = "sleeper_berth"
    DRIVING = "driving"
    ON_DUTY = "on_duty"


class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=gen_uuid)
    email = Column(String, unique=True, nullable=False, index=True)
    hashed_password = Column(String, nullable=False)
    full_name = Column(String, nullable=False)
    cdl_number = Column(String, nullable=True)
    company = Column(String, nullable=True)
    is_active = Column(Boolean, default=True)
    is_fleet_manager = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())


class TruckProfile(Base):
    __tablename__ = "truck_profiles"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, nullable=False, index=True)
    name = Column(String, nullable=False)  # "My Kenworth T680"
    height_meters = Column(Float, nullable=False, default=4.11)   # ~13'6"
    weight_kg = Column(Float, nullable=False, default=36287)      # ~80,000 lbs
    length_meters = Column(Float, nullable=False, default=22.86)  # ~75 ft
    width_meters = Column(Float, nullable=False, default=2.59)    # ~8'6"
    axle_count = Column(Integer, nullable=False, default=5)
    hazmat_class = Column(SAEnum(HazmatClass), default=HazmatClass.NONE)
    max_speed_mph = Column(Integer, default=65)
    is_default = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class HOSLog(Base):
    __tablename__ = "hos_logs"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, nullable=False, index=True)
    duty_status = Column(SAEnum(DutyStatus), nullable=False)
    start_time = Column(DateTime(timezone=True), nullable=False)
    end_time = Column(DateTime(timezone=True), nullable=True)
    location_name = Column(String, nullable=True)
    odometer_start = Column(Float, nullable=True)
    odometer_end = Column(Float, nullable=True)
    notes = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class TruckLocation(Base):
    __tablename__ = "truck_locations"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, nullable=False, index=True)
    location = Column(Geometry("POINT", srid=4326), nullable=False)
    speed_mph = Column(Float, default=0.0)
    heading_degrees = Column(Float, default=0.0)
    altitude_meters = Column(Float, default=0.0)
    accuracy_meters = Column(Float, default=0.0)
    recorded_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)


class Trip(Base):
    __tablename__ = "trips"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, nullable=False, index=True)
    truck_profile_id = Column(String, nullable=True)
    origin_name = Column(String, nullable=False)
    destination_name = Column(String, nullable=False)
    origin_lat = Column(Float, nullable=False)
    origin_lon = Column(Float, nullable=False)
    destination_lat = Column(Float, nullable=False)
    destination_lon = Column(Float, nullable=False)
    distance_miles = Column(Float, nullable=True)
    duration_hours = Column(Float, nullable=True)
    fuel_used_gallons = Column(Float, nullable=True)
    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    route_polyline = Column(Text, nullable=True)  # encoded polyline
    status = Column(String, default="planned")    # planned, active, completed, cancelled
    created_at = Column(DateTime(timezone=True), server_default=func.now())
