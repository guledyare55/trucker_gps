import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:trucker_gps/models/route_models.dart';

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
        width: 36,
        height: 36,
        child: _PoiIcon(poi: poi),
      );
    }).toList();

    return MarkerLayer(markers: markers);
  }
}

class _PoiIcon extends StatelessWidget {
  final PoiPoint poi;
  const _PoiIcon({required this.poi});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: poi.name,
      child: Container(
        decoration: BoxDecoration(
          color: _bgColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2))
          ],
        ),
        child: Icon(_icon, color: Colors.white, size: 18),
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
      default:
        return AppTheme.bg3;
    }
  }
}
