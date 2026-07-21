import 'package:flutter/material.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:trucker_gps/providers/navigation_provider.dart';

/// Displays the current turn instruction at the top of the screen during navigation.
class NavigationBanner extends StatelessWidget {
  final NavigationState navState;

  const NavigationBanner({super.key, required this.navState});

  @override
  Widget build(BuildContext context) {
    final step = navState.currentStep;
    final nextStep = navState.nextStep;

    if (step == null && navState.status != NavigationStatus.arrived) {
      return const SizedBox.shrink();
    }

    if (navState.status == NavigationStatus.arrived) {
      return _arrivedBanner();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: AppTheme.panelBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF252535)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main instruction row
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Direction icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _directionIcon(step!.type),
                    color: AppTheme.primary,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Distance to maneuver
                      if (navState.distanceToNextStepMeters != null)
                        Text(
                          _formatDistance(navState.distanceToNextStepMeters!),
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      Text(
                        step.instruction,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Next step preview
          if (nextStep != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                color: AppTheme.bg4.withOpacity(0.7),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Icon(_directionIcon(nextStep.type),
                      color: AppTheme.textMuted, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Then: ${nextStep.instruction}',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _arrivedBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.success.withOpacity(0.15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.success.withOpacity(0.5)),
      ),
      child: Row(
        children: const [
          Icon(Icons.check_circle, color: AppTheme.success, size: 36),
          SizedBox(width: 14),
          Text(
            'You have arrived!',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 160) {
      return '${meters.round()} ft';
    }
    final miles = meters / 1609.34;
    if (miles < 0.5) {
      return '${(miles * 5280).round()} ft';
    }
    return '${miles.toStringAsFixed(1)} mi';
  }

  IconData _directionIcon(String type) {
    switch (type.toLowerCase()) {
      case 'left':
      case 'turn-left':
        return Icons.turn_left;
      case 'right':
      case 'turn-right':
        return Icons.turn_right;
      case 'slight-left':
      case 'bear-left':
        return Icons.turn_slight_left;
      case 'slight-right':
      case 'bear-right':
        return Icons.turn_slight_right;
      case 'sharp-left':
        return Icons.turn_sharp_left;
      case 'sharp-right':
        return Icons.turn_sharp_right;
      case 'u-turn':
        return Icons.u_turn_left;
      case 'roundabout':
        return Icons.roundabout_right;
      case 'merge':
        return Icons.merge;
      case 'ramp':
      case 'exit':
        return Icons.exit_to_app;
      case 'arrive':
        return Icons.flag;
      default:
        return Icons.straight;
    }
  }
}
