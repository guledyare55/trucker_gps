from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    # App
    APP_NAME: str = "TruckerGPS API"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False
    SECRET_KEY: str = "change-me-in-production-use-random-256-bit-key"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days

    # Database
    DATABASE_URL: str = "postgresql+asyncpg://postgres:password@localhost:5432/truckergps"

    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"

    # OpenRouteService (free tier - 2000 req/day)
    ORS_API_KEY: str = ""
    ORS_BASE_URL: str = "https://api.openrouteservice.org"

    # Weather (Open-Meteo - completely free, no key needed)
    OPEN_METEO_URL: str = "https://api.open-meteo.com/v1"

    # OpenWeatherMap (for weather tile layers - free tier)
    OWM_API_KEY: str = ""
    OWM_BASE_URL: str = "https://api.openweathermap.org"

    # EIA Fuel Prices (free US government API)
    EIA_API_KEY: str = ""
    EIA_BASE_URL: str = "https://api.eia.gov/v2"

    # Overpass API (completely free)
    OVERPASS_URL: str = "https://overpass-api.de/api/interpreter"

    # CORS
    ALLOWED_ORIGINS: list[str] = ["*"]

    # Tile cache TTL (seconds)
    POI_CACHE_TTL: int = 86400        # 24 hours
    ROUTE_CACHE_TTL: int = 3600       # 1 hour
    WEATHER_CACHE_TTL: int = 900      # 15 minutes
    FUEL_CACHE_TTL: int = 3600        # 1 hour

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
