import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// Provides a continuous stream of the user's location
final locationStreamProvider = StreamProvider<Position>((ref) {
  const locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10, // Updates every 10 meters of movement
  );

  return Geolocator.getPositionStream(locationSettings: locationSettings);
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
