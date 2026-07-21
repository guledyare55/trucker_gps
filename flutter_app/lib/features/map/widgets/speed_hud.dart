import 'package:flutter/material.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';

/// Premium Garmin-style speed display with animated color transitions
class SpeedHud extends StatelessWidget {
  final double speedMph;

  const SpeedHud({super.key, required this.speedMph});

  @override
  Widget build(BuildContext context) {
    final speed = speedMph < 0 ? 0.0 : speedMph;
    final isOverSpeed = speed > 80;
    final speedColor = isOverSpeed ? AppTheme.danger : AppTheme.primary;

    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.panelBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOverSpeed
              ? AppTheme.danger.withOpacity(0.6)
              : const Color(0xFF252535),
          width: isOverSpeed ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isOverSpeed
                ? AppTheme.danger.withOpacity(0.2)
                : Colors.black38,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            speed.toStringAsFixed(0),
            style: TextStyle(
              color: speedColor,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1.0,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'MPH',
            style: TextStyle(
              color: isOverSpeed ? AppTheme.danger : AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
