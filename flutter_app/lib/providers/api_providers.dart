import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trucker_gps/services/api_service.dart';

// Provides a singleton instance of ApiService
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

// Provides current weather for a specific location
final currentWeatherProvider = FutureProvider.family<Map<String, dynamic>, Map<String, double>>((ref, coords) async {
  final apiService = ref.watch(apiServiceProvider);
  return apiService.getCurrentWeather(coords['lat']!, coords['lon']!);
});

// Provides HOS summary for a user
final hosSummaryProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, userId) async {
  final apiService = ref.watch(apiServiceProvider);
  return apiService.getHosSummary(userId);
});

// Provides diesel fuel prices
final fuelPricesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  return apiService.getFuelPrices();
});
