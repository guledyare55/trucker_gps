import 'package:flutter/material.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';

/// Premium Garmin-style speed display with smooth animated transitions
class SpeedHud extends StatelessWidget {
  final double speedMph;

  const SpeedHud({super.key, required this.speedMph});

  @override
  Widget build(BuildContext context) {
    final speed = speedMph < 0 ? 0.0 : speedMph;
    final displaySpeed = speed.toStringAsFixed(0);
    final isOverSpeed = speed > 80;
    final speedColor = isOverSpeed ? AppTheme.danger : AppTheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 80,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.panelBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOverSpeed
              ? AppTheme.danger.withOpacity(0.7)
              : const Color(0xFF252535),
          width: isOverSpeed ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isOverSpeed
                ? AppTheme.danger.withOpacity(0.3)
                : Colors.black38,
            blurRadius: isOverSpeed ? 20 : 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animate the speed number changing
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.3),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                child: child,
              ),
            ),
            child: Text(
              displaySpeed,
              key: ValueKey(displaySpeed),
              style: TextStyle(
                color: speedColor,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                height: 1.0,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: isOverSpeed ? AppTheme.danger : AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
            child: const Text('MPH'),
          ),
        ],
      ),
    );
  }
}
