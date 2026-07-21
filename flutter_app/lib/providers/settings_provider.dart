import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trucker_gps/models/settings_models.dart';
import 'package:trucker_gps/main.dart';

const _kSettingsKey = 'app_settings_v1';

class SettingsNotifier extends StateNotifier<AppSettings> {
  final dynamic _prefs;

  SettingsNotifier(this._prefs) : super(const AppSettings()) {
    _load();
  }

  void _load() {
    final raw = _prefs.getString(_kSettingsKey);
    if (raw != null) {
      try {
        state = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    await _prefs.setString(_kSettingsKey, jsonEncode(state.toJson()));
  }

  Future<void> setVehicleType(VehicleType type) async {
    state = state.copyWith(vehicleType: type);
    await _save();
  }

  Future<void> setAvoidTolls(bool value) async {
    state = state.copyWith(avoidTolls: value);
    await _save();
  }

  Future<void> setAvoidHighways(bool value) async {
    state = state.copyWith(avoidHighways: value);
    await _save();
  }

  Future<void> setVoiceEnabled(bool value) async {
    state = state.copyWith(voiceEnabled: value);
    await _save();
  }

  Future<void> setSpeedWarnings(bool value) async {
    state = state.copyWith(speedWarnings: value);
    await _save();
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return SettingsNotifier(prefs);
});
