import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';
import 'package:trucker_gps/models/route_models.dart';

// ── Navigation state ─────────────────────────────────────────────────────────

enum NavigationStatus { idle, routing, navigating, arrived }

class NavigationState {
  final NavigationStatus status;
  final TruckRoute? activeRoute;
  final int currentStepIndex;
  final double? distanceToNextStepMeters;
  final double? remainingDistanceMeters;   // live remaining trip distance
  final double? remainingDurationSeconds;  // live remaining trip time
  final String currentRoadName;            // e.g. "I-24" or "Main Street"
  final String currentRoadRef;             // raw OSM ref e.g. "I 24", "US 64"
  final List<LatLng> remainingPolyline;    // trimmed polyline from current position to end
  final PoiPoint? selectedPoi;
  final List<PoiPoint> nearbyPois;
  final String? error;
  final bool isLoading;
  
  // Routing preferences (saved for recalculation)
  final String? destinationName;
  final bool avoidTolls;
  final bool avoidHighways;

  const NavigationState({
    this.status = NavigationStatus.idle,
    this.activeRoute,
    this.currentStepIndex = 0,
    this.distanceToNextStepMeters,
    this.remainingDistanceMeters,
    this.remainingDurationSeconds,
    this.currentRoadName = '',
    this.currentRoadRef = '',
    this.remainingPolyline = const [],
    this.selectedPoi,
    this.nearbyPois = const [],
    this.error,
    this.isLoading = false,
    this.destinationName,
    this.avoidTolls = false,
    this.avoidHighways = false,
  });

  RouteStep? get currentStep =>
      activeRoute != null && currentStepIndex < activeRoute!.steps.length
          ? activeRoute!.steps[currentStepIndex]
          : null;

  RouteStep? get nextStep {
    if (activeRoute == null) return null;
    final next = currentStepIndex + 1;
    return next < activeRoute!.steps.length ? activeRoute!.steps[next] : null;
  }

  NavigationState copyWith({
    NavigationStatus? status,
    TruckRoute? activeRoute,
    int? currentStepIndex,
    double? distanceToNextStepMeters,
    double? remainingDistanceMeters,
    double? remainingDurationSeconds,
    String? currentRoadName,
    String? currentRoadRef,
    List<LatLng>? remainingPolyline,
    PoiPoint? selectedPoi,
    List<PoiPoint>? nearbyPois,
    String? error,
    bool? isLoading,
    bool clearRoute = false,
    bool clearError = false,
    bool clearPoi = false,
    String? destinationName,
    bool? avoidTolls,
    bool? avoidHighways,
  }) {
    return NavigationState(
      status: status ?? this.status,
      activeRoute: clearRoute ? null : (activeRoute ?? this.activeRoute),
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      distanceToNextStepMeters:
          distanceToNextStepMeters ?? this.distanceToNextStepMeters,
      remainingDistanceMeters: remainingDistanceMeters ?? this.remainingDistanceMeters,
      remainingDurationSeconds: remainingDurationSeconds ?? this.remainingDurationSeconds,
      currentRoadName: currentRoadName ?? this.currentRoadName,
      currentRoadRef: currentRoadRef ?? this.currentRoadRef,
      remainingPolyline: remainingPolyline ?? this.remainingPolyline,
      selectedPoi: clearPoi ? null : (selectedPoi ?? this.selectedPoi),
      nearbyPois: nearbyPois ?? this.nearbyPois,
      error: clearError ? null : (error ?? this.error),
      isLoading: isLoading ?? this.isLoading,
      destinationName: destinationName ?? this.destinationName,
      avoidTolls: avoidTolls ?? this.avoidTolls,
      avoidHighways: avoidHighways ?? this.avoidHighways,
    );
  }
}

// ── Navigation notifier ───────────────────────────────────────────────────────

class NavigationNotifier extends StateNotifier<NavigationState> {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  TruckProfile _truckProfile;
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRecalculation = DateTime.fromMillisecondsSinceEpoch(0);
  
  final Set<String> _announcedPoiIds = {};
  void Function(String)? onVoiceAlert;

  NavigationNotifier(this._truckProfile) : super(const NavigationState());

  TruckProfile get truckProfile => _truckProfile;

  void updateTruckProfile(TruckProfile profile) {
    _truckProfile = profile;
  }

  /// Calculate route using OSRM — completely free, no API key needed.
  /// Public server: router.project-osrm.org
  Future<void> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    String? destinationName,
    bool avoidTolls = false,
    bool avoidHighways = false,
    bool isAutoReroute = false,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, clearRoute: true);

    try {
      final excludes = <String>[];
      if (avoidTolls) excludes.add('toll');
      if (avoidHighways) excludes.add('motorway');
      final excludeParam =
          excludes.isNotEmpty ? '&exclude=${excludes.join(',')}' : '';

      final url =
          'https://router.project-osrm.org/route/v1/driving/'
          '${origin.longitude},${origin.latitude};'
          '${destination.longitude},${destination.latitude}'
          '?overview=full&geometries=geojson&steps=true&annotations=false$excludeParam';

      // Fetch raw string to avoid Dio blocking the main thread with JSON decoding
      final resp = await _dio.get(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      
      // Decode JSON on a background isolate
      final data = await compute(jsonDecode, resp.data.toString()) as Map<String, dynamic>;

      if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) {
        throw Exception('No route found between these locations');
      }

      final osrmRoute = data['routes'][0] as Map<String, dynamic>;
      final route = _parseOsrmRoute(osrmRoute, origin, destination);

      state = state.copyWith(
        status: isAutoReroute ? NavigationStatus.navigating : NavigationStatus.routing,
        activeRoute: route,
        currentStepIndex: 0,
        nearbyPois: [], // Clear old POIs
        isLoading: false,
        destinationName: destinationName,
        avoidTolls: avoidTolls,
        avoidHighways: avoidHighways,
        remainingDistanceMeters: route.distanceMeters,
        remainingDurationSeconds: route.durationSeconds,
        currentRoadName: route.steps.isNotEmpty ? route.steps.first.roadName : '',
        currentRoadRef: route.steps.isNotEmpty ? route.steps.first.roadRef : '',
        remainingPolyline: route.polyline,
      );

      // Fetch truck POIs along the route in the background (non-blocking)
      _fetchTruckPois(route).then((pois) {
        if (mounted) {
          state = state.copyWith(nearbyPois: pois);
        }
      });
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Routing failed: ${_friendlyError(e)}',
      );
    }
  }

  /// Parse OSRM GeoJSON response into TruckRoute model
  TruckRoute _parseOsrmRoute(
      Map<String, dynamic> osrmRoute, LatLng origin, LatLng destination) {
    // Decode polyline coordinates from GeoJSON
    final geometry = osrmRoute['geometry'] as Map<String, dynamic>;
    final coords = (geometry['coordinates'] as List)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();

    // Parse turn-by-turn steps from legs
    final steps = <RouteStep>[];
    for (final leg in (osrmRoute['legs'] as List)) {
      for (final step in (leg['steps'] as List? ?? [])) {
        final stepMap = step as Map<String, dynamic>;
        final maneuver = stepMap['maneuver'] as Map<String, dynamic>? ?? {};
        final location = maneuver['location'] as List? ?? [0.0, 0.0];
        final instruction = _buildInstruction(stepMap, maneuver);
        final maneuverType = maneuver['type'] as String? ?? 'straight';
        final modifier = maneuver['modifier'] as String? ?? '';

        // Extract lane guidance from intersections (OSRM feature)
        final intersections = stepMap['intersections'] as List? ?? [];
        final lanes = <LaneInfo>[];
        if (intersections.isNotEmpty) {
          final firstIntersection = intersections.first as Map<String, dynamic>? ?? {};
          final rawLanes = firstIntersection['lanes'] as List?;
          if (rawLanes != null) {
            for (final laneRaw in rawLanes) {
              final laneMap = laneRaw as Map<String, dynamic>? ?? {};
              final indications = ((laneMap['indications'] as List?) ?? [])
                  .map((e) => e.toString())
                  .toList();
              final isValid = laneMap['valid'] as bool? ?? false;
              lanes.add(LaneInfo(indications: indications, isValid: isValid));
            }
          }
        }

        steps.add(RouteStep(
          instruction: instruction,
          distanceMeters: (stepMap['distance'] as num?)?.toDouble() ?? 0,
          durationSeconds: (stepMap['duration'] as num?)?.toDouble() ?? 0,
          type: _mapOsrmType(maneuverType, modifier),
          location: LatLng(
            (location.length > 1 ? location[1] : 0).toDouble(),
            (location.isNotEmpty ? location[0] : 0).toDouble(),
          ),
          lanes: lanes,
          roadName: (stepMap['name'] as String?)?.trim() ?? '',
          roadRef: (stepMap['ref'] as String?)?.trim() ?? '',
        ));
      }
    }

    final distanceMeters =
        (osrmRoute['distance'] as num?)?.toDouble() ?? 0;
    final durationSeconds =
        (osrmRoute['duration'] as num?)?.toDouble() ?? 0;

    return TruckRoute(
      polyline: coords,
      steps: steps,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      durationFormatted: _formatDuration(durationSeconds),
      origin: coords.isNotEmpty ? coords.first : origin,
      destination: coords.isNotEmpty ? coords.last : destination,
    );
  }

  /// Build a human-readable instruction from OSRM step data
  String _buildInstruction(
      Map<String, dynamic> step, Map<String, dynamic> maneuver) {
    final name = (step['name'] as String?)?.trim() ?? '';
    final type = maneuver['type'] as String? ?? '';
    final modifier = maneuver['modifier'] as String? ?? '';
    final ref = step['ref'] as String? ?? '';
    final roadName = name.isNotEmpty ? name : (ref.isNotEmpty ? ref : 'the road');

    switch (type) {
      case 'depart':
        return 'Head ${modifier.isNotEmpty ? modifier : 'forward'} on $roadName';
      case 'arrive':
        return 'You have arrived at your destination';
      case 'turn':
        if (modifier.contains('left')) return 'Turn left onto $roadName';
        if (modifier.contains('right')) return 'Turn right onto $roadName';
        return 'Continue on $roadName';
      case 'new name':
        return 'Continue onto $roadName';
      case 'merge':
        return 'Merge onto $roadName';
      case 'ramp':
        if (modifier.contains('left')) return 'Take the ramp on the left';
        if (modifier.contains('right')) return 'Take the ramp on the right';
        return 'Take the ramp';
      case 'off ramp':
        return 'Take the exit onto $roadName';
      case 'fork':
        if (modifier.contains('left')) return 'Keep left at the fork';
        if (modifier.contains('right')) return 'Keep right at the fork';
        return 'Keep straight at the fork';
      case 'end of road':
        if (modifier.contains('left')) return 'Turn left at the end of the road';
        if (modifier.contains('right')) return 'Turn right at the end of the road';
        return 'Continue at the end of the road';
      case 'use lane':
        return 'Use the correct lane';
      case 'continue':
        return 'Continue on $roadName';
      case 'roundabout':
      case 'rotary':
        final exit = maneuver['exit'] as int?;
        if (exit != null) return 'Take exit $exit at the roundabout';
        return 'Enter the roundabout';
      default:
        return name.isNotEmpty ? 'Continue on $name' : 'Continue straight';
    }
  }

  String _mapOsrmType(String type, String modifier) {
    if (modifier.contains('left')) return 'turn-left';
    if (modifier.contains('right')) return 'turn-right';
    if (modifier.contains('slight left')) return 'slight-left';
    if (modifier.contains('slight right')) return 'slight-right';
    if (modifier.contains('sharp left')) return 'sharp-left';
    if (modifier.contains('sharp right')) return 'sharp-right';
    if (type == 'roundabout' || type == 'rotary') return 'roundabout';
    if (type == 'arrive') return 'arrive';
    if (type == 'merge') return 'merge';
    if (type == 'ramp' || type == 'off ramp') return 'ramp';
    return 'straight';
  }

  String _formatDuration(double seconds) {
    final h = (seconds ~/ 3600);
    final m = ((seconds % 3600) ~/ 60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  /// Fetch real truck POIs (truck stops, rest areas, weigh stations)
  /// from Overpass API — completely free, no API key needed.
  Future<List<PoiPoint>> _fetchTruckPois(TruckRoute route) async {
    if (route.polyline.isEmpty) return [];
    try {
      // Build bounding box from route
      double minLat = route.polyline.first.latitude;
      double maxLat = route.polyline.first.latitude;
      double minLon = route.polyline.first.longitude;
      double maxLon = route.polyline.first.longitude;
      for (final p in route.polyline) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLon) minLon = p.longitude;
        if (p.longitude > maxLon) maxLon = p.longitude;
      }

      // Overpass query for truck-relevant POIs
      final query = '''
[out:json][timeout:15];
(
  node["amenity"="fuel"]["hgv"="yes"]($minLat,$minLon,$maxLat,$maxLon);
  node["amenity"="fuel"]["truck"="yes"]($minLat,$minLon,$maxLat,$maxLon);
  node["highway"="rest_area"]($minLat,$minLon,$maxLat,$maxLon);
  node["highway"="services"]($minLat,$minLon,$maxLat,$maxLon);
  node["amenity"="truck_stop"]($minLat,$minLon,$maxLat,$maxLon);
  node["amenity"="rest_area"]($minLat,$minLon,$maxLat,$maxLon);
  node["amenity"="parking"]["hgv"="yes"]($minLat,$minLon,$maxLat,$maxLon);
  node["highway"="weigh_station"]($minLat,$minLon,$maxLat,$maxLon);
);
out body 40;
''';

      final resp = await _dio.post(
        'https://overpass-api.de/api/interpreter',
        data: query,
        options: Options(
          contentType: 'text/plain',
          headers: {'User-Agent': 'TruckerGPS/1.0'},
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      final elements = (resp.data['elements'] as List? ?? []);
      final pois = <PoiPoint>[];

      for (final el in elements) {
        final tags = el['tags'] as Map<String, dynamic>? ?? {};
        final lat = (el['lat'] as num?)?.toDouble();
        final lon = (el['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;

        final amenity = tags['amenity'] as String? ?? '';
        final highway = tags['highway'] as String? ?? '';
        final name = tags['name'] as String? ?? '';

        String type;
        String displayName;

        if (amenity == 'fuel' || amenity == 'truck_stop') {
          type = 'truck_stop';
          displayName = name.isNotEmpty ? name : 'Truck Fuel Stop';
        } else if (highway == 'rest_area' || amenity == 'rest_area') {
          type = 'rest_area';
          displayName = name.isNotEmpty ? name : 'Rest Area';
        } else if (highway == 'services') {
          type = 'truck_stop';
          displayName = name.isNotEmpty ? name : 'Service Area';
        } else if (amenity == 'parking') {
          type = 'truck_parking';
          displayName = name.isNotEmpty ? name : 'Truck Parking';
        } else if (highway == 'weigh_station') {
          type = 'weigh_station';
          displayName = name.isNotEmpty ? name : 'Weigh Station';
        } else {
          continue;
        }

        pois.add(PoiPoint(
          id: el['id']?.toString() ?? '$lat$lon',
          name: displayName,
          type: type,
          brand: tags['brand'] as String?,
          location: LatLng(lat, lon),
          amenities: _parseAmenities(tags),
        ));
      }

      return pois;
    } catch (_) {
      return []; // POIs are optional — silently ignore errors
    }
  }

  List<String> _parseAmenities(Map<String, dynamic> tags) {
    final a = <String>[];
    if (tags['shower'] == 'yes') a.add('Showers');
    if (tags['toilets'] == 'yes' || tags['amenity'] == 'toilets') a.add('Restrooms');
    if (tags['wifi'] == 'yes' || tags['internet_access'] == 'yes') a.add('WiFi');
    if (tags['restaurant'] == 'yes' || tags['amenity'] == 'restaurant') a.add('Restaurant');
    if (tags['fuel'] == 'yes' || tags['amenity'] == 'fuel') a.add('Diesel');
    if (tags['parking'] == 'yes') a.add('Parking');
    return a;
  }

  /// Search for nearby POIs by categories around a center point
  Future<void> searchNearbyPois(LatLng center, List<String> categories) async {
    if (categories.isEmpty) {
      state = state.copyWith(nearbyPois: []);
      return;
    }
    state = state.copyWith(isLoading: true);
    try {
      // Create a small bounding box around the center (~20km radius)
      final double latOffset = 0.2;
      final double lonOffset = 0.2 / cos(center.latitude * pi / 180);
      
      final minLat = center.latitude - latOffset;
      final maxLat = center.latitude + latOffset;
      final minLon = center.longitude - lonOffset;
      final maxLon = center.longitude + lonOffset;

      String queryTags = '';
      for (final category in categories) {
        switch (category) {
          case 'Truck Stop':
            queryTags += 'nwr["amenity"="truck_stop"]($minLat,$minLon,$maxLat,$maxLon); ';
            queryTags += 'nwr["highway"="rest_area"]($minLat,$minLon,$maxLat,$maxLon); ';
            queryTags += 'nwr["amenity"="rest_area"]($minLat,$minLon,$maxLat,$maxLon); ';
            // Include major brands by name or brand tag
            queryTags += "nwr[\"brand\"~\"Pilot|Flying J|TA|Petro|Love\",i]($minLat,$minLon,$maxLat,$maxLon); ";
            queryTags += "nwr[\"name\"~\"Pilot|Flying J|TA|Petro|TravelCenters of America|Love's\",i]($minLat,$minLon,$maxLat,$maxLon); ";
            break;
          case 'Fuel':
            queryTags += 'nwr["amenity"="fuel"]($minLat,$minLon,$maxLat,$maxLon); nwr["amenity"="truck_stop"]($minLat,$minLon,$maxLat,$maxLon); ';
            break;
          case 'Weigh Station':
            queryTags += 'nwr["highway"="weigh_station"]($minLat,$minLon,$maxLat,$maxLon); ';
            queryTags += 'nwr["amenity"="weigh_scale"]($minLat,$minLon,$maxLat,$maxLon); ';
            queryTags += "nwr[\"name\"~\"CAT Scale\",i]($minLat,$minLon,$maxLat,$maxLon); ";
            break;
          case 'Food':
            queryTags += 'nwr["amenity"="restaurant"]($minLat,$minLon,$maxLat,$maxLon); nwr["amenity"="fast_food"]($minLat,$minLon,$maxLat,$maxLon); ';
            break;
          default:
            queryTags += 'nwr["amenity"="$category"]($minLat,$minLon,$maxLat,$maxLon); ';
        }
      }

      final query = '''
[out:json][timeout:15];
(
  $queryTags
);
out center tags 40;
''';

      final resp = await _dio.post(
        'https://overpass-api.de/api/interpreter',
        data: query,
        options: Options(
          contentType: 'text/plain',
          headers: {'User-Agent': 'TruckerGPS/1.0'},
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final elements = (resp.data['elements'] as List? ?? []);
      final pois = <PoiPoint>[];

      for (final el in elements) {
        final tags = el['tags'] as Map<String, dynamic>? ?? {};
        final centerObj = el['center'] as Map<String, dynamic>?;
        final rawLat = el['lat'] ?? centerObj?['lat'];
        final rawLon = el['lon'] ?? centerObj?['lon'];
        final lat = (rawLat as num?)?.toDouble();
        final lon = (rawLon as num?)?.toDouble();
        if (lat == null || lon == null) continue;

        final name = _normalizeName(tags);
        
        // Infer type from tags
        String mappedType = 'truck_stop';
        if (tags['highway'] == 'weigh_station' || tags['amenity'] == 'weigh_scale' || name.toLowerCase().contains('scale')) mappedType = 'weigh_station';
        else if (tags['highway'] == 'rest_area' || tags['amenity'] == 'rest_area') mappedType = 'rest_area';
        else if (tags['amenity'] == 'restaurant' || tags['amenity'] == 'fast_food') mappedType = 'restaurant';
        else if (tags['amenity'] == 'parking' || tags['amenity'] == 'truck_parking') mappedType = 'truck_parking';

        pois.add(PoiPoint(
          id: el['id']?.toString() ?? '$lat$lon',
          name: name,
          type: mappedType,
          brand: tags['brand'] as String?,
          location: LatLng(lat, lon),
          amenities: _parseAmenities(tags),
        ));
      }

      state = state.copyWith(nearbyPois: pois, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Converts raw OSM tags into a clean, human-readable POI name.
  /// Prioritizes: recognized brand → cleaned raw name → type fallback.
  static String _normalizeName(Map<String, dynamic> tags) {
    final rawName     = tags['name']     as String? ?? '';
    final brand       = tags['brand']    as String? ?? '';
    final operator_   = tags['operator'] as String? ?? '';
    final amenity     = tags['amenity']  as String? ?? '';
    final highway     = tags['highway']  as String? ?? '';
    final ref         = tags['ref']      as String? ?? '';

    // ── 1. Recognized brand patterns ─────────────────────────────────────────
    final combined = '$rawName $brand $operator_'.toLowerCase();

    if (_matchesBrand(combined, ['pilot flying j', 'pilot travel center', 'pilot travel'])) {
      return 'Pilot Flying J Travel Center';
    }
    if (_matchesBrand(combined, ['flying j'])) {
      return 'Flying J Travel Plaza';
    }
    if (_matchesBrand(combined, ['pilot'])) {
      return 'Pilot Travel Center';
    }
    if (_matchesBrand(combined, ['ta travel center', 'travelcenters of america', 'travel centers of america'])) {
      return 'TA Travel Center';
    }
    if (_matchesBrand(combined, ['petro stopping center', 'petro travel center'])) {
      return 'Petro Stopping Center';
    }
    if (_matchesBrand(combined, ['petro'])) {
      return 'Petro Stopping Center';
    }
    if (_matchesBrand(combined, ["love's travel stop", "love's", 'loves travel'])) {
      return "Love's Travel Stop";
    }
    if (_matchesBrand(combined, ['kwik trip', 'kwik star'])) {
      return 'Kwik Trip';
    }
    if (_matchesBrand(combined, ['casey\'s', 'caseys'])) {
      return "Casey's General Store";
    }
    if (_matchesBrand(combined, ['flying star'])) {
      return 'Flying Star';
    }
    if (_matchesBrand(combined, ['cat scale', 'certified autoplex', 'cat weigh'])) {
      return 'CAT Scale';
    }
    if (_matchesBrand(combined, ['iowa 80'])) {
      return 'Iowa 80 Truckstop';
    }

    // ── 2. Rest areas / weigh stations ─────────────────────────────────────
    if (highway == 'weigh_station' || amenity == 'weigh_scale') {
      if (rawName.isNotEmpty) return _cleanName(rawName);
      return 'Weigh Station';
    }
    if (highway == 'rest_area' || amenity == 'rest_area') {
      if (rawName.isNotEmpty) {
        // e.g. "I-80 Rest Area MM 231" → keep as-is but clean
        return _cleanName(rawName);
      }
      final refStr = ref.isNotEmpty ? ' ($ref)' : '';
      return 'Rest Area$refStr';
    }
    if (amenity == 'truck_stop') {
      if (rawName.isNotEmpty) return _cleanName(rawName);
      return 'Truck Stop';
    }

    // ── 3. Use cleaned raw name if available ───────────────────────────────
    if (rawName.isNotEmpty) return _cleanName(rawName);

    return 'Truck Stop';
  }

  static bool _matchesBrand(String combined, List<String> keywords) {
    return keywords.any((k) => combined.contains(k));
  }

  /// Cleans up raw OSM names: trims whitespace, removes excessive codes.
  static String _cleanName(String name) {
    return name.trim();
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('connection')) {
      return 'No internet connection';
    }
    if (msg.contains('timeout')) return 'Request timed out — try again';
    if (msg.contains('No route')) return 'No route found between these locations';
    return 'Please check your connection and try again';
  }

  void startNavigation() {
    if (state.activeRoute != null) {
      state = state.copyWith(
          status: NavigationStatus.navigating, currentStepIndex: 0);
    }
  }

  void updateProgress(LatLng currentLocation) {
    if (state.activeRoute == null ||
        state.status != NavigationStatus.navigating) {
      return;
    }

    // Throttle: run at most every 400ms to avoid flooding the state notifier
    final now = DateTime.now();
    if (now.difference(_lastProgressUpdate).inMilliseconds < 400) return;
    _lastProgressUpdate = now;

    final steps = state.activeRoute!.steps;
    final idx = state.currentStepIndex;

    // Check arrival at final destination
    if (idx >= steps.length) {
      state = state.copyWith(status: NavigationStatus.arrived);
      return;
    }

    final currentStep = steps[idx];
    
    // Distance to the NEXT maneuver, or the destination if we're on the last step
    final targetLocation = idx < steps.length - 1 ? steps[idx + 1].location : currentStep.location;
    final dist = const Distance().as(
      LengthUnit.Meter,
      currentLocation,
      targetLocation,
    );

    // Voice Alerts for POIs
    for (final poi in state.nearbyPois) {
      if ((poi.type == 'weigh_station' || poi.type == 'rest_area') && !_announcedPoiIds.contains(poi.id)) {
        final poiDist = const Distance().as(LengthUnit.Meter, currentLocation, poi.location);
        if (poiDist < 3218) { // ~2 miles
          _announcedPoiIds.add(poi.id);
          final readableType = poi.type == 'weigh_station' ? 'Weigh station' : 'Rest area';
          onVoiceAlert?.call('$readableType approaching in 2 miles');
        }
      }
    }

    // Compute remaining distance = dist to next maneuver + sum of all future steps
    double remaining = dist;
    for (int i = idx + 1; i < steps.length; i++) {
      remaining += steps[i].distanceMeters;
    }
    // Remaining duration — proportional based on remaining/total distance
    final totalDist = state.activeRoute!.distanceMeters;
    final totalDur = state.activeRoute!.durationSeconds;
    final remainingDur = totalDist > 0 ? (remaining / totalDist) * totalDur : 0.0;

    // Trim polyline
    final polyline = state.activeRoute!.polyline;
    int closestIdx = 0;
    double minPolyDist = double.infinity;
    for (int i = 0; i < polyline.length; i++) {
      final d = const Distance().as(LengthUnit.Meter, currentLocation, polyline[i]);
      if (d < minPolyDist) {
        minPolyDist = d;
        closestIdx = i;
      }
    }
    // Only keep points from closest index onwards, plus the current location at the start
    final trimmedPolyline = [currentLocation, ...polyline.sublist(closestIdx)];

    // Current road info from the active step
    final roadName = currentStep.roadName;
    final roadRef = currentStep.roadRef;

    // Advance to next step when within 20m of the maneuver point
    final newIdx = (dist < 20 && idx < steps.length - 1) ? idx + 1 : idx;
    state = state.copyWith(
      currentStepIndex: newIdx,
      distanceToNextStepMeters: newIdx != idx
          ? const Distance().as(LengthUnit.Meter, currentLocation, steps[newIdx < steps.length - 1 ? newIdx + 1 : newIdx].location)
          : dist,
      remainingDistanceMeters: remaining,
      remainingDurationSeconds: remainingDur,
      currentRoadName: roadName,
      currentRoadRef: roadRef,
      remainingPolyline: trimmedPolyline,
    );

    // Check arrival: within 25m of the last step
    if (newIdx == steps.length - 1 && dist < 25) {
      state = state.copyWith(status: NavigationStatus.arrived);
      return;
    }

    // OFF-ROUTE DETECTION
    // Calculate precise cross-track distance to the route polyline.
    final crossTrackDist = _distanceToPolylineMeters(currentLocation, state.activeRoute!.polyline);
    
    // If the truck is more than 75 meters away from the route line, and we haven't recalculated in 5 seconds
    if (crossTrackDist > 75 && now.difference(_lastRecalculation).inSeconds > 5) {
      _lastRecalculation = now;
      
      // Keep the current destination but calculate a new route from the current location
      final dest = state.activeRoute!.destination;
      final destName = state.destinationName;
      
      calculateRoute(
        origin: currentLocation,
        destination: dest,
        destinationName: destName,
        avoidTolls: state.avoidTolls,
        avoidHighways: state.avoidHighways,
        isAutoReroute: true,
      );
    }
  }

  /// Calculates the shortest geometric distance from a point to a polyline.
  /// Uses a high-performance flat plane projection approximation.
  double _distanceToPolylineMeters(LatLng p, List<LatLng> polyline) {
    if (polyline.isEmpty) return double.infinity;
    if (polyline.length == 1) return const Distance().as(LengthUnit.Meter, p, polyline.first).toDouble();

    double minDist = double.infinity;

    final latRad = p.latitude * pi / 180.0;
    final cosLat = cos(latRad);
    const metersPerDeg = 111320.0;
    
    final px = p.longitude * cosLat * metersPerDeg;
    final py = p.latitude * metersPerDeg;

    for (int i = 0; i < polyline.length - 1; i++) {
      final v = polyline[i];
      final w = polyline[i + 1];

      final vx = v.longitude * cosLat * metersPerDeg;
      final vy = v.latitude * metersPerDeg;
      
      final wx = w.longitude * cosLat * metersPerDeg;
      final wy = w.latitude * metersPerDeg;
      
      final dx = wx - vx;
      final dy = wy - vy;
      
      final l2 = dx * dx + dy * dy;
      double dist;
      
      if (l2 == 0.0) {
        dist = sqrt((px - vx) * (px - vx) + (py - vy) * (py - vy));
      } else {
        final t = max(0.0, min(1.0, ((px - vx) * dx + (py - vy) * dy) / l2));
        final projX = vx + t * dx;
        final projY = vy + t * dy;
        dist = sqrt((px - projX) * (px - projX) + (py - projY) * (py - projY));
      }
      
      if (dist < minDist) minDist = dist;
    }
    
    return minDist;
  }

  void cancelNavigation() {
    _announcedPoiIds.clear();
    state = const NavigationState();
  }

  void selectPoi(PoiPoint poi) {
    state = state.copyWith(selectedPoi: poi);
  }

  void clearPoi() {
    state = state.copyWith(clearPoi: true);
  }
}

// ── Providers ────────────────────────────────────────────────────────────────

final truckProfileProvider = StateProvider<TruckProfile>((ref) {
  return const TruckProfile();
});

final navigationProvider =
    StateNotifierProvider<NavigationNotifier, NavigationState>((ref) {
  final profile = ref.watch(truckProfileProvider);
  return NavigationNotifier(profile);
});
