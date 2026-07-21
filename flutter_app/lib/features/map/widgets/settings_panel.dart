import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:trucker_gps/models/settings_models.dart';
import 'package:trucker_gps/providers/settings_provider.dart';
import 'package:trucker_gps/features/truck_profile/screens/truck_profile_screen.dart';
import 'package:trucker_gps/features/weather/screens/weather_screen.dart';
import 'package:trucker_gps/features/fuel/screens/fuel_screen.dart';

/// Shows the settings bottom sheet.
void showSettingsPanel(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ──────────────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A50),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // ── Title ───────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, color: AppTheme.primary, size: 22),
                SizedBox(width: 10),
                Text(
                  'Settings',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Vehicle Selector ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VEHICLE TYPE',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                _VehicleSelector(
                  selected: settings.vehicleType,
                  onSelect: notifier.setVehicleType,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Routing Preferences ─────────────────────────────────────────
          const _SectionHeader('ROUTING'),
          _ToggleTile(
            icon: Icons.toll_outlined,
            label: 'Avoid Tolls',
            subtitle: 'Take toll-free roads when possible',
            value: settings.avoidTolls,
            onChanged: notifier.setAvoidTolls,
          ),
          _ToggleTile(
            icon: Icons.alt_route_outlined,
            label: 'Avoid Highways',
            subtitle: 'Prefer local roads over freeways',
            value: settings.avoidHighways,
            onChanged: notifier.setAvoidHighways,
          ),

          // ── Navigation Preferences ──────────────────────────────────────
          const _SectionHeader('NAVIGATION'),
          _ToggleTile(
            icon: Icons.volume_up_outlined,
            label: 'Voice Navigation',
            subtitle: 'Spoken turn-by-turn instructions',
            value: settings.voiceEnabled,
            onChanged: notifier.setVoiceEnabled,
          ),
          _ToggleTile(
            icon: Icons.speed_outlined,
            label: 'Speed Alerts',
            subtitle: 'Warn when approaching speed limit',
            value: settings.speedWarnings,
            onChanged: notifier.setSpeedWarnings,
          ),

          // ── Tools & Features ────────────────────────────────────────────
          const SizedBox(height: 8),
          const _SectionHeader('FEATURES'),
          _NavTile(
            icon: Icons.person_outline,
            label: 'Truck Profile',
            subtitle: 'Height, weight & restrictions',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TruckProfileScreen()));
            },
          ),
          _NavTile(
            icon: Icons.local_gas_station_outlined,
            label: 'Fuel Prices',
            subtitle: 'Diesel prices near you',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const FuelScreen()));
            },
          ),
          _NavTile(
            icon: Icons.cloud_outlined,
            label: 'Weather',
            subtitle: 'Road weather & alerts',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const WeatherScreen()));
            },
          ),

          // Bottom safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }
}

// ── Vehicle Selector Chips ────────────────────────────────────────────────────

class _VehicleSelector extends StatelessWidget {
  final VehicleType selected;
  final void Function(VehicleType) onSelect;

  const _VehicleSelector({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _VehicleChip(
          icon: Icons.directions_car_rounded,
          label: 'Car / SUV',
          isSelected: selected == VehicleType.car,
          onTap: () => onSelect(VehicleType.car),
        ),
        const SizedBox(width: 12),
        _VehicleChip(
          icon: Icons.local_shipping_rounded,
          label: 'Semi Truck',
          isSelected: selected == VehicleType.truck,
          onTap: () => onSelect(VehicleType.truck),
        ),
      ],
    );
  }
}

class _VehicleChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _VehicleChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primary.withOpacity(0.15)
                : AppTheme.bg3,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppTheme.primary : const Color(0xFF2E2E3E),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                  size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                  fontSize: 13,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

// ── Toggle Tile ───────────────────────────────────────────────────────────────

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final void Function(bool) onChanged;

  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: Colors.transparent,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: value
                ? AppTheme.primary.withOpacity(0.12)
                : AppTheme.bg3,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              color: value ? AppTheme.primary : AppTheme.textMuted, size: 20),
        ),
        title: Text(
          label,
          style: TextStyle(
            color: value ? AppTheme.textPrimary : AppTheme.textMuted,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),
        trailing: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppTheme.primary,
          activeTrackColor: AppTheme.primary.withValues(alpha: 0.3),
          inactiveTrackColor: const Color(0xFF2E2E3E),
          inactiveThumbColor: AppTheme.textMuted,
        ),
      ),
    );
  }
}

// ── Navigation Tile ───────────────────────────────────────────────────────────

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: Colors.transparent,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.bg3,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.textPrimary, size: 20),
        ),
        title: Text(
          label,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppTheme.textMuted,
          size: 22,
        ),
      ),
    );
  }
}

