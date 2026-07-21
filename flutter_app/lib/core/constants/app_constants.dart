import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'TruckerGPS';

  // ── Backend URL (update this to your Render.com URL once deployed) ──────────
  // Android emulator => 10.0.2.2 maps to localhost on host machine
  // Physical device  => set to your Render URL e.g. https://truckergps-api.onrender.com
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://truckergps-api.onrender.com/api/v1',
  );

  static const String renderApiUrl = 'https://truckergps-api.onrender.com/api/v1';

  // ── Map ─────────────────────────────────────────────────────────────────────
  static const double defaultZoom = 16.0;
  static const double navigationZoom = 17.5;
  static const double overviewZoom = 12.0;
  static const double minZoom = 3.0;
  static const double maxZoom = 22.0;

  // ── OSM Tile layers ──────────────────────────────────────────────────────────
  static const String osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String osmDarkTileUrl = 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
  static const String osmSatelliteUrl = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  // ── Storage keys ─────────────────────────────────────────────────────────────
  static const String truckProfileKey = 'truck_profile_v2';
  static const String settingsKey = 'app_settings_v2';
  static const String recentSearchesKey = 'recent_searches';

  // ── Default truck dimensions (US standard 18-wheeler) ───────────────────────
  static const double defaultHeightM = 4.11;   // 13'6"
  static const double defaultWeightKg = 36287;  // 80,000 lbs
  static const double defaultLengthM = 22.86;   // 75 ft
  static const double defaultWidthM = 2.59;     // 8'6"

  // ── POI icon map ─────────────────────────────────────────────────────────────
  static const Map<String, IconData> poiIcons = {
    'truck_stop': Icons.local_gas_station,
    'weigh_station': Icons.monitor_weight,
    'rest_area': Icons.park,
    'truck_parking': Icons.local_parking,
    'fuel': Icons.local_gas_station,
  };
}
