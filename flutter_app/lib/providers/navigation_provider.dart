import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:trucker_gps/models/route_models.dart';
import 'package:trucker_gps/services/api_service.dart';
import 'package:trucker_gps/providers/api_providers.dart';

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
      distanceToNextStepMeters: distanceToNextStepMeters ?? this.distanceToNextStepMeters,
      selectedPoi: clearPoi ? null : (selectedPoi ?? this.selectedPoi),
      nearbyPois: nearbyPois ?? this.nearbyPois,
      error: clearError ? null : (error ?? this.error),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// ── Navigation notifier ───────────────────────────────────────────────────────

class NavigationNotifier extends StateNotifier<NavigationState> {
  final ApiService _api;
  TruckProfile _truckProfile;

  NavigationNotifier(this._api, this._truckProfile)
      : super(const NavigationState());

  TruckProfile get truckProfile => _truckProfile;

  void updateTruckProfile(TruckProfile profile) {
    _truckProfile = profile;
  }

  Future<void> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    String? destinationName,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, clearRoute: true);

    try {
      final result = await _api.getRoute(
        startLat: origin.latitude,
        startLon: origin.longitude,
        endLat: destination.latitude,
        endLon: destination.longitude,
        truckProfile: _truckProfile.toJson(),
      );

      final route = TruckRoute.fromJson(result);

      // Fetch POIs along the route
      final pois = await _fetchPoisAlongRoute(route);

      state = state.copyWith(
        status: NavigationStatus.routing,
        activeRoute: route,
        currentStepIndex: 0,
        nearbyPois: pois,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to calculate route: $e',
      );
    }
  }

  Future<List<PoiPoint>> _fetchPoisAlongRoute(TruckRoute route) async {
    if (route.polyline.isEmpty) return [];

    // Sample a few points along the route to search for POIs
    try {
      // Get bounding box of route
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

      final pois = await _api.getPoisInBbox(minLat, minLon, maxLat, maxLon);
      return pois
          .map((p) => PoiPoint.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void startNavigation() {
    if (state.activeRoute != null) {
      state = state.copyWith(status: NavigationStatus.navigating, currentStepIndex: 0);
    }
  }

  void updateProgress(LatLng currentLocation) {
    if (state.activeRoute == null || state.status != NavigationStatus.navigating) return;

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

    // Auto-advance to next step when within 30 meters
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
  return const TruckProfile(); // Default 18-wheeler
});

final navigationProvider =
    StateNotifierProvider<NavigationNotifier, NavigationState>((ref) {
  final api = ref.watch(apiServiceProvider);
  final profile = ref.watch(truckProfileProvider);
  return NavigationNotifier(api, profile);
});
