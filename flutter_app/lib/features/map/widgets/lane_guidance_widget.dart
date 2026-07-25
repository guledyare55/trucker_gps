import 'package:flutter/material.dart';
import 'package:trucker_gps/models/route_models.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';

/// Displays lane arrows for the upcoming maneuver, like a real commercial GPS.
/// Shows each lane with appropriate direction arrows; the correct lanes are
/// highlighted in bright green, invalid lanes are dimmed.
class LaneGuidanceWidget extends StatelessWidget {
  final List<LaneInfo> lanes;

  const LaneGuidanceWidget({super.key, required this.lanes});

  @override
  Widget build(BuildContext context) {
    // Don't render if no lane data available
    if (lanes.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(
          top: BorderSide(color: AppTheme.primary.withValues(alpha: 0.2), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: lanes.map((lane) => _buildLaneArrow(lane)).toList(),
      ),
    );
  }

  Widget _buildLaneArrow(LaneInfo lane) {
    final isValid = lane.isValid;
    final color = isValid ? AppTheme.primary : Colors.white.withValues(alpha: 0.25);

    // Determine which arrow icon to use based on primary indication
    final primary = lane.indications.isNotEmpty ? lane.indications.first : 'straight';
    final icon = _indicationIcon(primary, lane.indications);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isValid
              ? AppTheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color,
            width: isValid ? 1.5 : 1,
          ),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  IconData _indicationIcon(String indication, List<String> all) {
    // Check for merged lane types like ['straight', 'right']
    final hasLeft = all.contains('left') || all.contains('sharp left') || all.contains('slight left');
    final hasRight = all.contains('right') || all.contains('sharp right') || all.contains('slight right');
    final hasStraight = all.contains('straight') || all.contains('none');

    if (hasStraight && hasRight) return Icons.turn_slight_right_rounded;
    if (hasStraight && hasLeft) return Icons.turn_slight_left_rounded;

    switch (indication) {
      case 'left':
        return Icons.turn_left_rounded;
      case 'sharp left':
        return Icons.turn_sharp_left_rounded;
      case 'slight left':
        return Icons.turn_slight_left_rounded;
      case 'right':
        return Icons.turn_right_rounded;
      case 'sharp right':
        return Icons.turn_sharp_right_rounded;
      case 'slight right':
        return Icons.turn_slight_right_rounded;
      case 'uturn':
        return Icons.u_turn_right_rounded;
      case 'straight':
      case 'none':
      default:
        return Icons.straight_rounded;
    }
  }
}
