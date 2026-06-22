import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class RobotStatusBar extends StatelessWidget {
  final bool spineConnected;
  final bool isMoving;
  final int battery;

  const RobotStatusBar({
    Key? key,
    required this.spineConnected,
    required this.isMoving,
    required this.battery,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: MikeeColors.surface,
        border: Border(
          bottom: BorderSide(color: MikeeColors.border),
        ),
      ),
      child: Row(
        children: [
          // Spine status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: spineConnected ? MikeeColors.success.withOpacity(0.2) : MikeeColors.error.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: spineConnected ? MikeeColors.success : MikeeColors.error,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  spineConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: spineConnected ? MikeeColors.success : MikeeColors.error,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  spineConnected ? 'Connected' : 'Disconnected',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: spineConnected ? MikeeColors.success : MikeeColors.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Moving status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isMoving ? MikeeColors.primary.withOpacity(0.2) : MikeeColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.directions_run,
                  color: isMoving ? MikeeColors.primary : MikeeColors.textSecondary,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  isMoving ? 'Moving' : 'Idle',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isMoving ? MikeeColors.primary : MikeeColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),

          // Battery
          Icon(
            battery > 20 ? Icons.battery_full : Icons.battery_alert,
            color: battery > 20 ? MikeeColors.success : MikeeColors.warning,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            '${battery}%',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: battery > 20 ? MikeeColors.success : MikeeColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}
