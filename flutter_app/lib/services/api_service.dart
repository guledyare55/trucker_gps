import 'package:dio/dio.dart';
import 'package:trucker_gps/core/constants/app_constants.dart';

class ApiService {
  final Dio _dio;

  ApiService()
      : _dio = Dio(BaseOptions(
          baseUrl: AppConstants.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Content-Type': 'application/json'},
        ));

  // --- Routing ---
  Future<Map<String, dynamic>> getRoute({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
    required Map<String, dynamic> truckProfile,
  }) async {
    try {
      final response = await _dio.post('/routing/route', data: {
        'start_lat': startLat,
        'start_lon': startLon,
        'end_lat': endLat,
        'end_lon': endLon,
        'height_meters': truckProfile['height_meters'] ?? 4.11,
        'weight_kg': truckProfile['weight_kg'] ?? 36287.0,
        'length_meters': truckProfile['length_meters'] ?? 22.86,
        'width_meters': truckProfile['width_meters'] ?? 2.59,
        'axle_load_kg': truckProfile['axle_load_kg'] ?? 9000.0,
        'hazmat': truckProfile['hazmat'] ?? false,
      });
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // --- POI ---
  Future<List<dynamic>> getPoisInBbox(
      double south, double west, double north, double east,
      {String? types}) async {
    try {
      final query = {
        'south': south,
        'west': west,
        'north': north,
        'east': east,
      };
      if (types != null) query['types'] = types;

      final response = await _dio.get('/poi/bbox', queryParameters: query);
      return response.data['pois'] ?? [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<dynamic>> searchTruckStops(String query, double lat, double lon) async {
    try {
      final response = await _dio.get('/poi/search', queryParameters: {
        'q': query,
        'lat': lat,
        'lon': lon,
      });
      return response.data['results'] ?? [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  // --- Weather ---
  Future<Map<String, dynamic>> getCurrentWeather(double lat, double lon) async {
    try {
      final response = await _dio.get('/weather/current', queryParameters: {
        'lat': lat,
        'lon': lon,
      });
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // --- HOS ---
  Future<Map<String, dynamic>> getHosSummary(String userId) async {
    try {
      final response = await _dio.get('/hos/summary/$userId');
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> updateDutyStatus(String userId, String dutyStatus, {String? notes}) async {
    try {
      await _dio.post('/hos/status', data: {
        'user_id': userId,
        'duty_status': dutyStatus,
        'notes': notes,
      });
    } catch (e) {
      throw _handleError(e);
    }
  }

  // --- Fuel ---
  Future<Map<String, dynamic>> getFuelPrices() async {
    try {
      final response = await _dio.get('/fuel/prices');
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Exception _handleError(dynamic error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data != null && data is Map && data['detail'] != null) {
        return Exception(data['detail']);
      }
      return Exception(error.message);
    }
    return Exception(error.toString());
  }
}
