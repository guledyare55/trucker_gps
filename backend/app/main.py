from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
import logging

from app.core.config import settings
from app.core.database import init_db, close_db
from app.api import routing, poi, weather, hos, fuel, fleet

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown lifecycle."""
    logger.info("🚛 TruckerGPS API starting up...")
    try:
        await init_db()
        logger.info("✅ Database initialized")
    except Exception as e:
        logger.warning(f"⚠️ Database init skipped (not configured): {e}")
    yield
    logger.info("🛑 TruckerGPS API shutting down...")
    await close_db()


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="""
# TruckerGPS API 🚛

A Garmin OTR-class GPS backend for professional truck drivers.

## Features
- 🗺️ **Truck Routing** via OpenRouteService HGV profile (height/weight/hazmat)
- 📍 **POI Search** for truck stops, weigh stations, rest areas (OpenStreetMap)
- 🌦️ **Weather** with truck-specific wind/ice alerts (Open-Meteo, NOAA)
- 📋 **HOS/ELD** FMCSA-compliant hours-of-service tracking
- ⛽ **Fuel Prices** US regional diesel prices (EIA)
- 🚛 **Fleet Management** real-time location tracking via WebSocket

## Authentication
Currently open for development. Add JWT auth via the `Authorization: Bearer <token>` header.
""",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# ─── CORS ──────────────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Exception Handlers ────────────────────────────────────────────────────────
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error", "type": type(exc).__name__},
    )


# ─── Routers ───────────────────────────────────────────────────────────────────
app.include_router(routing.router, prefix="/api/v1")
app.include_router(poi.router, prefix="/api/v1")
app.include_router(weather.router, prefix="/api/v1")
app.include_router(hos.router, prefix="/api/v1")
app.include_router(fuel.router, prefix="/api/v1")
app.include_router(fleet.router, prefix="/api/v1")


# ─── Health Check ──────────────────────────────────────────────────────────────
@app.get("/", tags=["Health"])
async def root():
    return {
        "service": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "status": "🟢 Running",
        "docs": "/docs",
    }


@app.get("/health", tags=["Health"])
async def health_check():
    from app.core.database import get_redis
    redis_ok = False
    try:
        redis = await get_redis()
        await redis.ping()
        redis_ok = True
    except Exception:
        pass

    return {
        "status": "healthy",
        "redis": "connected" if redis_ok else "disconnected",
        "version": settings.APP_VERSION,
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
