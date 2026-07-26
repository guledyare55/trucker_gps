import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// Provides a continuous stream of the user's location
final locationStreamProvider = StreamProvider<Position>((ref) async* {
  const locationSettings = LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 5, // 5m balance: real-time feel without flooding the main thread
  );

  // Emit current position immediately so UI doesn't hang waiting for movement
  try {
    var pos = await Geolocator.getLastKnownPosition();
    if (pos != null) {
      yield pos;
    } else {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        ),
      );
      yield pos;
    }
  } catch (_) {
    // If GPS is disabled or times out, yield a default fallback to prevent UI hang
    yield Position(
      longitude: -98.5795,
      latitude: 39.8283,
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
  }

  // Then yield updates
  yield* Geolocator.getPositionStream(locationSettings: locationSettings);
});

// A derived provider that just yields the LatLng for mapping
final currentLatLngProvider = Provider<LatLng?>((ref) {
  final positionAsync = ref.watch(locationStreamProvider);
  return positionAsync.when(
    data: (position) => LatLng(position.latitude, position.longitude),
    loading: () => null,
    error: (err, stack) => null,
  );
});

// Provides current speed in MPH
final currentSpeedMphProvider = Provider<double>((ref) {
  final positionAsync = ref.watch(locationStreamProvider);
  return positionAsync.when(
    data: (position) {
      // position.speed is in meters/second. Convert to mph: 1 m/s = 2.23694 mph
      return position.speed * 2.23694;
    },
    loading: () => 0.0,
    error: (err, stack) => 0.0,
  );
});
