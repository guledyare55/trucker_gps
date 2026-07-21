import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Represents a decoded routing step for turn-by-turn navigation
class RouteStep {
  final String instruction;
  final double distanceMeters;
  final double durationSeconds;
  final String type;       // 'left', 'right', 'straight', 'roundabout', etc.
  final int? exitNumber;
  final LatLng location;

  const RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.type,
    this.exitNumber,
    required this.location,
  });

  String get distanceMiles => '${(distanceMeters / 1609.34).toStringAsFixed(1)} mi';

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    final coords = json['location'] as List? ?? [0.0, 0.0];
    return RouteStep(
      instruction: json['instruction'] ?? '',
      distanceMeters: (json['distance_meters'] ?? 0).toDouble(),
      durationSeconds: (json['duration_seconds'] ?? 0).toDouble(),
      type: json['type'] ?? 'straight',
      exitNumber: json['exit_number'],
      location: LatLng(
        (coords.length > 1 ? coords[1] : 0).toDouble(),
        (coords.length > 0 ? coords[0] : 0).toDouble(),
      ),
    );
  }
}

/// Full truck route model
class TruckRoute {
  final List<LatLng> polyline;
  final List<RouteStep> steps;
  final double distanceMeters;
  final double durationSeconds;
  final String durationFormatted;
  final LatLng origin;
  final LatLng destination;

  const TruckRoute({
    required this.polyline,
    required this.steps,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.durationFormatted,
    required this.origin,
    required this.destination,
  });

  double get distanceMiles => distanceMeters / 1609.34;

  factory TruckRoute.fromJson(Map<String, dynamic> json) {
    final coords = (json['polyline'] as List? ?? [])
        .map((c) => LatLng(
              (c[1] as num).toDouble(),
              (c[0] as num).toDouble(),
            ))
        .toList();

    final steps = (json['steps'] as List? ?? [])
        .map((s) => RouteStep.fromJson(s as Map<String, dynamic>))
        .toList();

    return TruckRoute(
      polyline: coords,
      steps: steps,
      distanceMeters: (json['distance_meters'] ?? 0).toDouble(),
      durationSeconds: (json['duration_seconds'] ?? 0).toDouble(),
      durationFormatted: json['duration_formatted'] ?? '',
      origin: coords.isNotEmpty ? coords.first : const LatLng(0, 0),
      destination: coords.isNotEmpty ? coords.last : const LatLng(0, 0),
    );
  }
}

/// Truck profile for restriction routing
class TruckProfile {
  final double heightMeters;
  final double weightKg;
  final double lengthMeters;
  final double widthMeters;
  final double axleLoadKg;
  final bool hazmat;
  final bool hazmatExplosive;
  final String vehicleName;

  const TruckProfile({
    this.heightMeters = 4.11,
    this.weightKg = 36287,
    this.lengthMeters = 22.86,
    this.widthMeters = 2.59,
    this.axleLoadKg = 9000,
    this.hazmat = false,
    this.hazmatExplosive = false,
    this.vehicleName = 'My Truck',
  });

  Map<String, dynamic> toJson() => {
        'height_meters': heightMeters,
        'weight_kg': weightKg,
        'length_meters': lengthMeters,
        'width_meters': widthMeters,
        'axle_load_kg': axleLoadKg,
        'hazmat': hazmat,
        'hazmat_explosive': hazmatExplosive,
      };

  String get heightFtIn {
    final totalInches = (heightMeters * 39.3701).round();
    return "${totalInches ~/ 12}'${totalInches % 12}\"";
  }

  String get weightLbs => '${(weightKg * 2.20462).round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')} lbs';
}

/// POI point on or near route
class PoiPoint {
  final String id;
  final String name;
  final String type;
  final String? brand;
  final LatLng location;
  final List<String> amenities;
  final double? distanceFromRouteMiles;

  const PoiPoint({
    required this.id,
    required this.name,
    required this.type,
    this.brand,
    required this.location,
    this.amenities = const [],
    this.distanceFromRouteMiles,
  });

  factory PoiPoint.fromJson(Map<String, dynamic> json) {
    return PoiPoint(
      id: json['id']?.toString() ?? UniqueKey().toString(),
      name: json['name'] ?? 'Unknown',
      type: json['type'] ?? 'poi',
      brand: json['brand'],
      location: LatLng(
        (json['lat'] ?? 0).toDouble(),
        (json['lon'] ?? 0).toDouble(),
      ),
      amenities: List<String>.from(json['amenities'] ?? []),
    );
  }
}
