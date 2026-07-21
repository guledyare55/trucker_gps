import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:trucker_gps/providers/api_providers.dart';
import 'package:trucker_gps/providers/location_provider.dart';

class WeatherScreen extends ConsumerWidget {
  const WeatherScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posAsync = ref.watch(locationStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Road Weather')),
      body: posAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Location unavailable: $e')),
        data: (pos) {
          final weatherAsync = ref.watch(
              currentWeatherProvider({'lat': pos.latitude, 'lon': pos.longitude}));

          return weatherAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            error: (e, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: AppTheme.textMuted),
                  const SizedBox(height: 16),
                  Text('Weather unavailable', style: const TextStyle(color: AppTheme.textMuted)),
                  Text('$e', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ],
              ),
            ),
            data: (weather) => _WeatherContent(weather: weather),
          );
        },
      ),
    );
  }
}

class _WeatherContent extends StatelessWidget {
  final Map<String, dynamic> weather;
  const _WeatherContent({required this.weather});

  @override
  Widget build(BuildContext context) {
    final current = weather['current'] ?? {};
    final alerts = weather['alerts'] as List? ?? [];
    final forecast = weather['hourly_forecast'] as List? ?? [];

    final temp = current['temperature_f'] ?? current['temperature'] ?? '--';
    final wind = current['wind_speed_mph'] ?? current['windspeed'] ?? '--';
    final desc = current['description'] ?? current['weathercode'] ?? 'Clear';
    final humidity = current['humidity'] ?? '--';
    final visibility = current['visibility_miles'] ?? '--';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Severe alerts
          if (alerts.isNotEmpty) ...[
            ...alerts.map((alert) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.danger.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppTheme.danger, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          alert['headline'] ?? alert.toString(),
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
          ],

          // Current conditions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Current Conditions',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.wb_sunny_outlined,
                          color: AppTheme.warning, size: 48),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$temp°F',
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 36,
                                fontWeight: FontWeight.w800),
                          ),
                          Text('$desc',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 15)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _weatherStat(Icons.air, 'Wind', '$wind mph'),
                      const SizedBox(width: 24),
                      _weatherStat(Icons.water_drop, 'Humidity', '$humidity%'),
                      const SizedBox(width: 24),
                      _weatherStat(Icons.visibility, 'Visibility', '$visibility mi'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Driving advisory
          _drivingAdvisory(wind is num ? wind.toDouble() : 0.0),

          const SizedBox(height: 20),

          // Forecast
          if (forecast.isNotEmpty) ...[
            const Text('Route Forecast',
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16)),
            const SizedBox(height: 12),
            ...forecast.take(6).map((h) => _forecastRow(h)).toList(),
          ],
        ],
      ),
    );
  }

  Widget _weatherStat(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.primary, size: 20),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        Text(value,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _drivingAdvisory(double windMph) {
    String advisory;
    Color color;
    IconData icon;

    if (windMph > 50) {
      advisory = 'HIGH WIND WARNING — Extreme caution required. High-profile vehicles at serious risk.';
      color = AppTheme.danger;
      icon = Icons.dangerous;
    } else if (windMph > 35) {
      advisory = 'Wind Advisory — Reduce speed. High-profile vehicles may experience handling issues.';
      color = AppTheme.warning;
      icon = Icons.warning_amber;
    } else {
      advisory = 'Driving conditions appear normal. Stay alert for changing weather.';
      color = AppTheme.success;
      icon = Icons.check_circle_outline;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(advisory,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _forecastRow(Map<String, dynamic> h) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(h['time'] ?? '', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, width: 1)),
          const SizedBox(width: 16),
          const Icon(Icons.wb_sunny_outlined, color: AppTheme.warning, size: 18),
          const SizedBox(width: 8),
          Text('${h['temperature_f'] ?? h['temperature'] ?? '--'}°F',
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          const Icon(Icons.air, color: AppTheme.info, size: 16),
          const SizedBox(width: 4),
          Text('${h['wind_speed_mph'] ?? h['windspeed'] ?? '--'} mph',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}
