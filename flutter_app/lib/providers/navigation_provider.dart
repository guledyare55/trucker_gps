import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  final PoiPoint? selectedPoi;
  final List<PoiPoint> nearbyPois;
  final String? error;
  final bool isLoading;

  const NavigationState({
    this.status = NavigationStatus.idle,
    this.activeRoute,
    this.currentStepIndex = 0,
    this.distanceToNextStepMeters,
    this.selectedPoi,
    this.nearbyPois = const [],
    this.error,
    this.isLoading = false,
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
    PoiPoint? selectedPoi,
    List<PoiPoint>? nearbyPois,
    String? error,
    bool? isLoading,
    bool clearRoute = false,
    bool clearError = false,
    bool clearPoi = false,
  }) {
    return NavigationState(
      status: status ?? this.status,
      activeRoute: clearRoute ? null : (activeRoute ?? this.activeRoute),
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      distanceToNextStepMeters:
          distanceToNextStepMeters ?? this.distanceToNextStepMeters,
      selectedPoi: clearPoi ? null : (selectedPoi ?? this.selectedPoi),
      nearbyPois: nearbyPois ?? this.nearbyPois,
      error: clearError ? null : (error ?? this.error),
      isLoading: isLoading ?? this.isLoading,
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
          '?overview=simplified&geometries=geojson&steps=true&annotations=false$excludeParam';

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
        status: NavigationStatus.routing,
        activeRoute: route,
        currentStepIndex: 0,
        nearbyPois: [], // Clear old POIs
        isLoading: false,
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

        steps.add(RouteStep(
          instruction: instruction,
          distanceMeters: (stepMap['distance'] as num?)?.toDouble() ?? 0,
          durationSeconds: (stepMap['duration'] as num?)?.toDouble() ?? 0,
          type: _mapOsrmType(maneuverType, modifier),
          location: LatLng(
            (location.length > 1 ? location[1] : 0).toDouble(),
            (location.isNotEmpty ? location[0] : 0).toDouble(),
          ),
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

    final steps = state.activeRoute!.steps;
    if (state.currentStepIndex >= steps.length) {
      state = state.copyWith(status: NavigationStatus.arrived);
      return;
    }

    final currentStep = steps[state.currentStepIndex];
    final dist = const Distance().as(
      LengthUnit.Meter,
      currentLocation,
      currentStep.location,
    );

    if (dist < 30 && state.currentStepIndex < steps.length - 1) {
      state = state.copyWith(
        currentStepIndex: state.currentStepIndex + 1,
        distanceToNextStepMeters: dist,
      );
    } else {
      state = state.copyWith(distanceToNextStepMeters: dist);
    }
  }

  void cancelNavigation() {
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
