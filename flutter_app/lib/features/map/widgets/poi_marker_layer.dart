import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:trucker_gps/models/route_models.dart';
import 'package:trucker_gps/providers/location_provider.dart';
import 'package:trucker_gps/providers/navigation_provider.dart';
import 'package:trucker_gps/providers/settings_provider.dart';

/// Renders POI icons (truck stops, weigh stations, rest areas) on the map.
class PoiMarkerLayer extends StatelessWidget {
  final List<PoiPoint> pois;

  const PoiMarkerLayer({super.key, required this.pois});

  @override
  Widget build(BuildContext context) {
    if (pois.isEmpty) return const SizedBox.shrink();

    final markers = pois.map((poi) {
      return Marker(
        point: poi.location,
        width: 44,
        height: 44,
        child: _PoiIcon(poi: poi),
      );
    }).toList();

    return MarkerLayer(markers: markers);
  }
}

class _PoiIcon extends StatelessWidget {
  final PoiPoint poi;
  const _PoiIcon({required this.poi});

  void _showPoiDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PoiBottomSheet(poi: poi),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPoiDetails(context),
      child: Tooltip(
        message: poi.name,
        child: Container(
          decoration: BoxDecoration(
            color: _bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3))
            ],
          ),
          child: Icon(_icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  IconData get _icon {
    switch (poi.type) {
      case 'truck_stop':
      case 'fuel':
        return Icons.local_gas_station;
      case 'weigh_station':
        return Icons.monitor_weight;
      case 'rest_area':
        return Icons.park;
      case 'truck_parking':
        return Icons.local_parking;
      case 'restaurant':
        return Icons.restaurant;
      default:
        return Icons.place;
    }
  }

  Color get _bgColor {
    switch (poi.type) {
      case 'truck_stop':
      case 'fuel':
        return const Color(0xFF1565C0);
      case 'weigh_station':
        return const Color(0xFFB71C1C);
      case 'rest_area':
        return const Color(0xFF2E7D32);
      case 'truck_parking':
        return const Color(0xFFE65100);
      case 'restaurant':
        return const Color(0xFFD84315);
      default:
        return AppTheme.bg3;
    }
  }
}

class _PoiBottomSheet extends ConsumerWidget {
  final PoiPoint poi;
  const _PoiBottomSheet({required this.poi});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(locationStreamProvider);
    final settings = ref.watch(settingsProvider);

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A50),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Header
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.place, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poi.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _typeLabel(poi),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Amenities
          if (poi.amenities.isNotEmpty) ...[
            const Text(
              'AMENITIES',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: poi.amenities.map((a) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.bg3,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2E2E3E)),
                  ),
                  child: Text(
                    a,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
          ],

          // Route Button
          ElevatedButton(
            onPressed: () {
              locationAsync.whenData((pos) {
                Navigator.pop(context);
                ref.read(navigationProvider.notifier).calculateRoute(
                      origin: LatLng(pos.latitude, pos.longitude),
                      destination: poi.location,
                      destinationName: poi.name,
                      avoidTolls: settings.avoidTolls,
                      avoidHighways: settings.avoidHighways,
                    );
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.directions, size: 20),
                SizedBox(width: 8),
                Text('Navigate Here', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _typeLabel(PoiPoint poi) {
    switch (poi.type) {
      case 'truck_stop':
      case 'fuel':
        return '⛽ Truck Stop / Travel Center';
      case 'weigh_station':
        return '⚖️ Weigh Station';
      case 'rest_area':
        return '🌿 Rest Area';
      case 'truck_parking':
        return '🅿️ Truck Parking';
      case 'restaurant':
        return '🍽️ Restaurant';
      default:
        return poi.type.replaceAll('_', ' ').toUpperCase();
    }
  }
}
