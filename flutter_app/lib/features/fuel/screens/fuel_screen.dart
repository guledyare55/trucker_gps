import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:trucker_gps/providers/api_providers.dart';

class FuelScreen extends ConsumerWidget {
  const FuelScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fuelAsync = ref.watch(fuelPricesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Diesel Fuel Prices')),
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
        data: (fuel) => _FuelContent(fuel: fuel),
      ),
    );
  }
}

class _FuelContent extends StatelessWidget {
  final Map<String, dynamic> fuel;
  const _FuelContent({required this.fuel});

  @override
  Widget build(BuildContext context) {
    final national = fuel['national_avg_diesel'] ?? 0.0;
    final regions = fuel['regional_prices'] as Map<String, dynamic>? ?? {};
    final updatedAt = fuel['updated_at'] ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // National average card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A2A4A), Color(0xFF0A1628)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.local_gas_station,
                      color: AppTheme.primary, size: 32),
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('US National Avg Diesel',
                        style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      '\$${national.toStringAsFixed(3)}',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'per gallon • Updated: $updatedAt',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          const Text(
            'REGIONAL PRICES',
            style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2),
          ),
          const SizedBox(height: 12),

          if (regions.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Regional price data currently unavailable.',
                    style: TextStyle(color: AppTheme.textMuted)),
              ),
            )
          else
            ...regions.entries.map((entry) {
              final price = (entry.value as num?)?.toDouble() ?? 0.0;
              final diff = price - (national as num).toDouble();
              return _RegionRow(
                  region: entry.key, price: price, nationalDiff: diff);
            }).toList(),

          const SizedBox(height: 24),

          // Fuel calc tip
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bg3,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF252535)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('💡 Fuel Saving Tips',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                SizedBox(height: 10),
                Text('• Drive 60–65 mph for optimal fuel economy',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                Text('• Use cruise control on open highways',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                Text('• Pre-plan fuel stops in lower-cost regions',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                Text('• Idle reduction saves ~1 gallon/hour',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionRow extends StatelessWidget {
  final String region;
  final double price;
  final double nationalDiff;

  const _RegionRow(
      {required this.region, required this.price, required this.nationalDiff});

  @override
  Widget build(BuildContext context) {
    final isAbove = nationalDiff > 0;
    final color = isAbove ? AppTheme.danger : AppTheme.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF252535)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(region,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
          ),
          Text('\$${price.toStringAsFixed(3)}',
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Text(
            '${isAbove ? '+' : ''}\$${nationalDiff.toStringAsFixed(3)}',
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
