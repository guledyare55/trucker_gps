# TruckerGPS 🚛

A full-stack, Garmin OTR-class GPS navigation system for professional truck drivers.

## Tech Stack
* **Frontend:** Flutter (iOS, Android, Desktop)
* **Backend:** Python / FastAPI
* **Database:** PostgreSQL + PostGIS + Redis
* **Mapping/Routing:** OpenStreetMap, OpenRouteService
* **Weather:** Open-Meteo, NOAA
* **Fuel:** EIA (US Government)

## 🚀 Getting Started

### 1. Backend Setup (Python)

The backend handles truck-specific routing, POI fetching, HOS calculations, and real-time fleet WebSocket connections.

```bash
cd backend
python -m venv venv
# Windows: venv\Scripts\activate
# Mac/Linux: source venv/bin/activate

pip install -r requirements.txt
cp .env.example .env
```
*Note: Make sure to set your API keys in the `.env` file (ORS, OWM, EIA) or use the free fallbacks!*

Start the backend:
```bash
uvicorn app.main:app --reload
```
The API docs will be available at `http://localhost:8000/docs`.

### 2. Frontend Setup (Flutter)

The mobile app displays the live map, handles GPS tracking, and communicates with the backend.

```bash
cd flutter_app
flutter pub get
```

Start the app on an emulator or connected device:
```bash
flutter run
```

## Features Implemented

* **Backend Services:**
  * `routing_service.py`: ORS truck routing with height, weight, length, hazmat restrictions.
  * `poi_service.py`: Overpass API queries for truck stops, weigh stations, parking.
  * `weather_service.py`: Free Open-Meteo current weather and route weather, plus severe NOAA alerts.
  * `hos_service.py`: FMCSA-compliant HOS calculation (11/14/70 rules).
  * `fuel_service.py`: EIA diesel prices.
  * `fleet.py`: WebSocket real-time tracking for fleet managers.
* **Frontend:**
  * Clean Material 3 UI with Dark/Light modes.
  * `flutter_map` integration with OSM tiles.
  * Location permissions and tracking.
  * Base navigation map screen with layout.

## Next Steps for Development
- Build the remaining UI screens (Truck Profile setup, POI search sheet, HOS Logbook).
- Connect the Flutter Riverpod providers directly to the FastAPI endpoints.
- Configure PostgreSQL/PostGIS database locally (currently defaults to an in-memory or SQLite if not set up, though the URI points to Postgres).
