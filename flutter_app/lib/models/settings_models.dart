enum VehicleType { car, truck }

class AppSettings {
  final VehicleType vehicleType;
  final bool avoidTolls;
  final bool avoidHighways;
  final bool voiceEnabled;
  final bool speedWarnings;

  const AppSettings({
    this.vehicleType = VehicleType.truck,
    this.avoidTolls = false,
    this.avoidHighways = false,
    this.voiceEnabled = true,
    this.speedWarnings = true,
  });

  AppSettings copyWith({
    VehicleType? vehicleType,
    bool? avoidTolls,
    bool? avoidHighways,
    bool? voiceEnabled,
    bool? speedWarnings,
  }) {
    return AppSettings(
      vehicleType: vehicleType ?? this.vehicleType,
      avoidTolls: avoidTolls ?? this.avoidTolls,
      avoidHighways: avoidHighways ?? this.avoidHighways,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      speedWarnings: speedWarnings ?? this.speedWarnings,
    );
  }

  Map<String, dynamic> toJson() => {
        'vehicleType': vehicleType.name,
        'avoidTolls': avoidTolls,
        'avoidHighways': avoidHighways,
        'voiceEnabled': voiceEnabled,
        'speedWarnings': speedWarnings,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      vehicleType: VehicleType.values.firstWhere(
        (e) => e.name == json['vehicleType'],
        orElse: () => VehicleType.truck,
      ),
      avoidTolls: json['avoidTolls'] ?? false,
      avoidHighways: json['avoidHighways'] ?? false,
      voiceEnabled: json['voiceEnabled'] ?? true,
      speedWarnings: json['speedWarnings'] ?? true,
    );
  }
}
