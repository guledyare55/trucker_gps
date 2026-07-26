import 'package:flutter/material.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:trucker_gps/providers/navigation_provider.dart';
import 'package:trucker_gps/features/map/widgets/lane_guidance_widget.dart';

/// Displays the current turn instruction at the top of the screen during navigation.
class NavigationBanner extends StatelessWidget {
  final NavigationState navState;
  final VoidCallback onCancel;

  const NavigationBanner({super.key, required this.navState, required this.onCancel});

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
      width: double.infinity,
      color: const Color(0xFF003833),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                // Turn arrow
                Icon(
                  _directionIcon(step!.type),
                  color: Colors.white,
                  size: 56,
                ),
                const SizedBox(width: 16),
                // Distance & Street
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (navState.distanceToNextStepMeters != null)
                        Text(
                          _formatDistance(navState.distanceToNextStepMeters!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        step.instruction,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
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
          // Lane Guidance
          if (step.lanes != null && step.lanes!.isNotEmpty)
            Container(
              width: double.infinity,
              color: AppTheme.bg2,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: LaneGuidanceWidget(lanes: step.lanes!),
            ),
          // Next maneuver (if applicable)
          if (nextStep != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF002B27),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _directionIcon(nextStep.type),
                    color: Colors.white60,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Then: ${nextStep.instruction}',
                      style: const TextStyle(color: Colors.white60, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
                        'Then: ${nextStep.instruction}',
                        style: const TextStyle(color: Colors.white60, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            // Lane Guidance
            if (step.lanes.isNotEmpty)
              Container(
                width: double.infinity,
                color: const Color(0xFF002B27),
                padding: const EdgeInsets.only(bottom: 12),
                child: LaneGuidanceWidget(lanes: step.lanes),
              ),
          ],
        ),
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
        children: [
          const Icon(Icons.check_circle, color: AppTheme.success, size: 36),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'You have arrived!',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close, color: AppTheme.textPrimary),
            tooltip: 'Clear Route',
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
