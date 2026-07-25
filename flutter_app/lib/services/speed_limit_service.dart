import 'dart:async';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

/// Fetches the posted speed limit from OpenStreetMap via the Overpass API.
/// Results are cached per road segment to minimize API calls.
class SpeedLimitService {
  static final SpeedLimitService _instance = SpeedLimitService._internal();
  factory SpeedLimitService() => _instance;
  SpeedLimitService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  // Cache: store a fetched speed limit with the lat/lon key of the query center
  final Map<String, int?> _cache = {};
  LatLng? _lastQueryLocation;

  /// Returns the speed limit in MPH, or null if not found.
  Future<int?> getSpeedLimit(LatLng location) async {
    // Only query if moved more than ~200 meters from the last query
    if (_lastQueryLocation != null) {
      final dist = const Distance().as(
        LengthUnit.Meter,
        location,
        _lastQueryLocation!,
      );
      if (dist < 200) {
        // Return cached result
        final key = _cacheKey(_lastQueryLocation!);
        return _cache[key];
      }
    }

    _lastQueryLocation = location;
    final key = _cacheKey(location);

    if (_cache.containsKey(key)) return _cache[key];

    try {
      // Query Overpass for nearby roads with maxspeed tags within 30m radius
      final query = '''
[out:json][timeout:10];
way(around:30,${location.latitude},${location.longitude})[highway][maxspeed];
out tags 1;
''';
      final resp = await _dio.get(
        'https://overpass-api.de/api/interpreter',
        queryParameters: {'data': query},
      );

      final elements = (resp.data['elements'] as List?) ?? [];
      if (elements.isNotEmpty) {
        final tags = elements.first['tags'] as Map<String, dynamic>? ?? {};
        final rawSpeed = tags['maxspeed'] as String?;
        final speedMph = _parseSpeedLimit(rawSpeed);
        _cache[key] = speedMph;
        return speedMph;
      }
    } catch (_) {
      // Fail silently — speed limit is informational only
    }

    _cache[key] = null;
    return null;
  }

  /// Parse OSM maxspeed tag to MPH integer.
  /// Handles formats: "65 mph", "105 km/h", "65", "55 mph", etc.
  int? _parseSpeedLimit(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final lower = raw.toLowerCase().trim();

    // Handle special tags
    if (lower == 'none') return null; // No limit road
    if (lower == 'walk' || lower == 'walking') return 5;
    if (lower == 'urban') return 25;
    if (lower == 'rural') return 55;

    // Extract numeric part
    final numMatch = RegExp(r'(\d+)').firstMatch(lower);
    if (numMatch == null) return null;
    final val = int.parse(numMatch.group(1)!);

    if (lower.contains('km') || lower.contains('kph')) {
      return (val * 0.621371).round();
    }
    // Default assumption is already MPH in the US
    return val;
  }

  String _cacheKey(LatLng l) =>
      '${l.latitude.toStringAsFixed(4)},${l.longitude.toStringAsFixed(4)}';

  void clearCache() {
    _cache.clear();
    _lastQueryLocation = null;
  }
}
