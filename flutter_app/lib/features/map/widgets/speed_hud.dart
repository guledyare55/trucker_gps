import 'package:flutter/material.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';

/// Garmin-style speed display with large readable text
class SpeedHud extends StatelessWidget {
  final double speedMph;

  const SpeedHud({Key? key, required this.speedMph}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final speed = speedMph < 0 ? 0.0 : speedMph;
    // Color warning when speed is unusually high (>80 mph)
    final speedColor = speed > 80 ? AppTheme.danger : AppTheme.textPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.panelBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF252535)),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            speed.toStringAsFixed(0),
            style: TextStyle(
              color: speedColor,
              fontSize: 40,
              fontWeight: FontWeight.w900,
              height: 1.0,
              letterSpacing: -2,
            ),
          ),
          const Text(
            'mph',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
