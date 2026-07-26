import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trucker_gps/services/api_service.dart';
import 'package:trucker_gps/services/weather_service.dart';
import 'package:trucker_gps/services/fuel_service.dart';
import 'package:trucker_gps/providers/location_provider.dart';

// Singleton services
final apiServiceProvider = Provider<ApiService>((ref) => ApiService());
final weatherServiceProvider = Provider<WeatherService>((ref) => WeatherService());
final fuelServiceProvider = Provider<FuelService>((ref) => FuelService());

// Provides current weather for specific coordinates
final currentWeatherProvider = FutureProvider.family<Map<String, dynamic>, Map<String, double>>((ref, coords) async {
  final weatherService = ref.watch(weatherServiceProvider);
  return weatherService.getWeather(coords['lat']!, coords['lon']!);
});

// Provides diesel fuel prices & nearby stations based on location
final fuelPricesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final fuelService = ref.watch(fuelServiceProvider);
  final posAsync = ref.watch(locationStreamProvider);
  final pos = posAsync.valueOrNull;
  return fuelService.getFuelPrices(
    userLat: pos?.latitude,
    userLon: pos?.longitude,
  );
});

// Provides HOS summary for a user
final hosSummaryProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, userId) async {
  final apiService = ref.watch(apiServiceProvider);
  return apiService.getHosSummary(userId);
});
