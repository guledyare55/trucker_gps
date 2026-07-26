import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:trucker_gps/providers/api_providers.dart';
import 'package:trucker_gps/providers/navigation_provider.dart';
import 'package:trucker_gps/providers/location_provider.dart';

class FuelScreen extends ConsumerStatefulWidget {
  const FuelScreen({super.key});

  @override
  ConsumerState<FuelScreen> createState() => _FuelScreenState();
}

class _FuelScreenState extends ConsumerState<FuelScreen> {
  bool _sortByPrice = false; // false = sort by distance, true = sort by price

  @override
  Widget build(BuildContext context) {
    final fuelAsync = ref.watch(fuelPricesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diesel Fuel & Truck Stops'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(fuelPricesProvider),
            tooltip: 'Refresh Prices',
          ),
        ],
      ),
      body: fuelAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_gas_station, size: 64, color: AppTheme.textMuted),
              const SizedBox(height: 16),
              const Text('Fuel data unavailable',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 16)),
              const SizedBox(height: 8),
              Text('$e', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
        ),
        data: (fuel) => _buildContent(context, ref, fuel),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, Map<String, dynamic> fuel) {
    final national = (fuel['national_avg_diesel'] as num?)?.toDouble() ?? 3.789;
    final updatedAt = fuel['updated_at'] ?? 'Today';
    final rawStations = (fuel['stations'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];

    final stations = List<Map<String, dynamic>>.from(rawStations);
    if (_sortByPrice) {
      stations.sort((a, b) => (a['diesel_price'] as double).compareTo(b['diesel_price'] as double));
    } else {
      stations.sort((a, b) => (a['distance_miles'] as double).compareTo(b['distance_miles'] as double));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // National Average Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF162544), Color(0xFF0D172B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.local_gas_station, color: AppTheme.primary, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('US NATIONAL AVG DIESEL',
                          style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                      const SizedBox(height: 2),
                      Text(
                        '\$${national.toStringAsFixed(3)}',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'per gal • $updatedAt',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Header + Sort Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NEARBY TRUCK STOPS (${stations.length})',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.bg2,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2A2A3C)),
                ),
                child: Row(
                  children: [
                    _sortTab('Closest', !_sortByPrice, () => setState(() => _sortByPrice = false)),
                    _sortTab('Cheapest', _sortByPrice, () => setState(() => _sortByPrice = true)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Station List
          if (stations.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No truck stops found nearby.', style: TextStyle(color: AppTheme.textMuted)),
              ),
            )
          else
            ...stations.map((st) => _buildStationCard(context, ref, st)),
        ],
      ),
    );
  }

  Widget _sortTab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppTheme.textMuted,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildStationCard(BuildContext context, WidgetRef ref, Map<String, dynamic> st) {
    final name = st['name'] ?? 'Truck Stop';
    final brand = st['brand'] ?? 'Fuel';
    final price = (st['diesel_price'] as num?)?.toDouble() ?? 0.0;
    final cashPrice = (st['cash_price'] as num?)?.toDouble();
    final dist = (st['distance_miles'] as num?)?.toDouble() ?? 0.0;
    final defAtPump = st['def_at_pump'] == true;
    final showers = st['showers'] as int? ?? 0;
    final parking = st['parking_spaces'] as int? ?? 0;
    final lat = (st['lat'] as num?)?.toDouble();
    final lon = (st['lon'] as num?)?.toDouble();

    final brandColor = _getBrandColor(brand);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF28283C)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: brandColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  brand.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$dist mi away',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Price Tag
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${price.toStringAsFixed(3)}',
                    style: const TextStyle(
                      color: AppTheme.success,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (cashPrice != null)
                    Text(
                      'Cash: \$${cashPrice.toStringAsFixed(3)}',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: Color(0xFF28283C), height: 1),
          const SizedBox(height: 10),

          // Amenities & Route Action
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (defAtPump) _amenityTag(Icons.opacity, 'DEF', Colors.lightBlue),
                    if (parking > 0) _amenityTag(Icons.local_parking, '$parking Spaces', Colors.amber),
                    if (showers > 0) _amenityTag(Icons.shower, '$showers Showers', Colors.teal),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (lat != null && lon != null)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.navigation, size: 16),
                  label: const Text('Route', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  onPressed: () {
                    final posAsync = ref.read(locationStreamProvider);
                    posAsync.whenData((pos) {
                      ref.read(navigationProvider.notifier).calculateRoute(
                            origin: LatLng(pos.latitude, pos.longitude),
                            destination: LatLng(lat, lon),
                            destinationName: name,
                          );
                      Navigator.of(context).pop();
                    });
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _amenityTag(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Color _getBrandColor(String brand) {
    switch (brand.toLowerCase()) {
      case 'love\'s':
        return const Color(0xFFD32F2F); // Love's Red
      case 'pilot':
      case 'flying j':
        return const Color(0xFFC62828); // Pilot Red
      case 'ta':
      case 'petro':
        return const Color(0xFF1565C0); // TA Blue
      case 'speedway':
        return const Color(0xFFE65100); // Speedway Orange
      case 'circle k':
        return const Color(0xFFB71C1C);
      case 'shell':
        return const Color(0xFFF57F17); // Shell Yellow/Orange
      default:
        return const Color(0xFF455A64);
    }
  }
}
