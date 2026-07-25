import 'package:flutter/material.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';

/// Renders a standard US Speed Limit road sign with dynamic warning coloring.
class SpeedLimitSign extends StatelessWidget {
  final int? speedLimit;
  final double currentSpeedMph;

  const SpeedLimitSign({
    super.key,
    required this.speedLimit,
    required this.currentSpeedMph,
  });

  @override
  Widget build(BuildContext context) {
    // Hide if no speed limit data yet
    if (speedLimit == null) return const SizedBox.shrink();

    final isOverLimit = currentSpeedMph > speedLimit! + 5;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 52,
      decoration: BoxDecoration(
        color: isOverLimit
            ? AppTheme.danger.withValues(alpha: 0.15)
            : AppTheme.panelBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOverLimit ? AppTheme.danger : const Color(0xFF252535),
          width: isOverLimit ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isOverLimit
                ? AppTheme.danger.withValues(alpha: 0.4)
                : Colors.black38,
            blurRadius: isOverLimit ? 18 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SPEED',
              style: TextStyle(
                color: isOverLimit ? AppTheme.danger : AppTheme.textMuted,
                fontSize: 7,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'LIMIT',
              style: TextStyle(
                color: isOverLimit ? AppTheme.danger : AppTheme.textMuted,
                fontSize: 7,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            // Divider line like a real sign
            Container(height: 1, color: isOverLimit ? AppTheme.danger : Colors.white24),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                '$speedLimit',
                key: ValueKey(speedLimit),
                style: TextStyle(
                  color: isOverLimit ? AppTheme.danger : Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  letterSpacing: -1,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'MPH',
              style: TextStyle(
                color: isOverLimit ? AppTheme.danger : AppTheme.textMuted,
                fontSize: 7,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
