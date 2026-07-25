enum VehicleType { car, truck }
enum MapThemeMode { light, dark, system, auto }

class AppSettings {
  final VehicleType vehicleType;
  final bool avoidTolls;
  final bool avoidHighways;
  final bool voiceEnabled;
  final bool speedWarnings;
  final MapThemeMode mapThemeMode;
  final bool showSpeedHud;

  const AppSettings({
    this.vehicleType = VehicleType.truck,
    this.avoidTolls = false,
    this.avoidHighways = false,
    this.voiceEnabled = true,
    this.speedWarnings = true,
    this.mapThemeMode = MapThemeMode.auto,
    this.showSpeedHud = true,
  });

  AppSettings copyWith({
    VehicleType? vehicleType,
    bool? avoidTolls,
    bool? avoidHighways,
    bool? voiceEnabled,
    bool? speedWarnings,
    MapThemeMode? mapThemeMode,
    bool? showSpeedHud,
  }) {
    return AppSettings(
      vehicleType: vehicleType ?? this.vehicleType,
      avoidTolls: avoidTolls ?? this.avoidTolls,
      avoidHighways: avoidHighways ?? this.avoidHighways,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      speedWarnings: speedWarnings ?? this.speedWarnings,
      mapThemeMode: mapThemeMode ?? this.mapThemeMode,
      showSpeedHud: showSpeedHud ?? this.showSpeedHud,
    );
  }

  Map<String, dynamic> toJson() => {
        'vehicleType': vehicleType.name,
        'avoidTolls': avoidTolls,
        'avoidHighways': avoidHighways,
        'voiceEnabled': voiceEnabled,
        'speedWarnings': speedWarnings,
        'mapThemeMode': mapThemeMode.name,
        'showSpeedHud': showSpeedHud,
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
      mapThemeMode: MapThemeMode.values.firstWhere(
        (e) => e.name == json['mapThemeMode'],
        orElse: () => MapThemeMode.auto,
      ),
      showSpeedHud: json['showSpeedHud'] ?? true,
    );
  }
}
