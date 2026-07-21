import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:trucker_gps/core/constants/app_constants.dart';
import 'package:trucker_gps/models/route_models.dart';
import 'package:trucker_gps/providers/navigation_provider.dart';

class TruckProfileScreen extends ConsumerStatefulWidget {
  const TruckProfileScreen({super.key});

  @override
  ConsumerState<TruckProfileScreen> createState() => _TruckProfileScreenState();
}

class _TruckProfileScreenState extends ConsumerState<TruckProfileScreen> {
  late double _height;
  late double _weight;
  late double _length;
  late double _width;
  late bool _hazmat;
  final _vehicleNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final profile = ref.read(truckProfileProvider);
    _height = profile.heightMeters;
    _weight = profile.weightKg;
    _length = profile.lengthMeters;
    _width = profile.widthMeters;
    _hazmat = profile.hazmat;
    _vehicleNameCtrl.text = profile.vehicleName;
  }

  void _save() {
    ref.read(truckProfileProvider.notifier).state = TruckProfile(
      heightMeters: _height,
      weightKg: _weight,
      lengthMeters: _length,
      widthMeters: _width,
      hazmat: _hazmat,
      vehicleName: _vehicleNameCtrl.text.trim().isEmpty
          ? 'My Truck'
          : _vehicleNameCtrl.text.trim(),
    );
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Truck profile saved!'),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Truck Profile'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Routes are automatically calculated to avoid low bridges, weight-restricted roads, and no-truck zones based on your profile.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            TextField(
              controller: _vehicleNameCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Vehicle Name',
                prefixIcon: Icon(Icons.local_shipping_outlined),
              ),
            ),
            const SizedBox(height: 28),

            _sectionTitle('Height'),
            _buildSlider(
              value: _height,
              min: 2.5,
              max: 5.0,
              label: '${(_height * 39.3701 / 12).floor()}\'${((_height * 39.3701) % 12).floor()}" (${_height.toStringAsFixed(2)} m)',
              onChanged: (v) => setState(() => _height = v),
              color: _height > 4.2 ? AppTheme.warning : AppTheme.primary,
            ),

            _sectionTitle('Weight (GVW)'),
            _buildSlider(
              value: _weight,
              min: 5000,
              max: 80000,
              label: '${(_weight * 2.20462).round().toString()} lbs (${(_weight / 1000).toStringAsFixed(1)} tonnes)',
              onChanged: (v) => setState(() => _weight = v),
              color: _weight > 36287 ? AppTheme.warning : AppTheme.primary,
            ),

            _sectionTitle('Length'),
            _buildSlider(
              value: _length,
              min: 6.0,
              max: 30.0,
              label: '${(_length * 3.28084).toStringAsFixed(1)} ft (${_length.toStringAsFixed(1)} m)',
              onChanged: (v) => setState(() => _length = v),
              color: AppTheme.primary,
            ),

            _sectionTitle('Width'),
            _buildSlider(
              value: _width,
              min: 2.0,
              max: 3.5,
              label: '${(_width * 3.28084).toStringAsFixed(1)} ft (${_width.toStringAsFixed(2)} m)',
              onChanged: (v) => setState(() => _width = v),
              color: AppTheme.primary,
            ),

            const SizedBox(height: 24),
            _sectionTitle('Special Restrictions'),
            Card(
              child: SwitchListTile(
                title: const Text('Hazmat / Dangerous Goods',
                    style: TextStyle(color: AppTheme.textPrimary)),
                subtitle: const Text(
                    'Avoid tunnels and restricted hazmat routes',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                value: _hazmat,
                onChanged: (v) => setState(() => _hazmat = v),
                activeThumbColor: AppTheme.warning,
                secondary: Icon(
                  Icons.warning_amber_rounded,
                  color: _hazmat ? AppTheme.warning : AppTheme.textMuted,
                ),
              ),
            ),

            const SizedBox(height: 36),

            // Quick presets
            _sectionTitle('Quick Presets'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _presetChip('Standard 18-Wheeler', 4.11, 36287, 22.86, 2.59),
                _presetChip('Box Truck', 3.81, 11340, 7.32, 2.44),
                _presetChip('Oversized Load', 4.57, 45000, 26.5, 3.0),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _buildSlider({
    required double value,
    required double min,
    required double max,
    required String label,
    required ValueChanged<double> onChanged,
    Color? color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color ?? AppTheme.primary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color ?? AppTheme.primary,
            thumbColor: color ?? AppTheme.primary,
            inactiveTrackColor: AppTheme.bg4,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _presetChip(String label, double h, double w, double l, double wid) {
    return ActionChip(
      label: Text(label),
      backgroundColor: AppTheme.bg3,
      labelStyle: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      onPressed: () => setState(() {
        _height = h;
        _weight = w;
        _length = l;
        _width = wid;
      }),
    );
  }

  @override
  void dispose() {
    _vehicleNameCtrl.dispose();
    super.dispose();
  }
}
