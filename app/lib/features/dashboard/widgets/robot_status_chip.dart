import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class RobotStatusChip extends StatelessWidget {
  final bool online;
  final int battery;
  final VoidCallback? onTap;

  const RobotStatusChip({
    Key? key,
    required this.online,
    required this.battery,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final statusColor = online ? TimoColors.success : TimoColors.error;
    const statusText = 'ONLINE';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: TimoColors.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: TimoColors.border),
                ),
                child: Text(
                  '${battery}%',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: TimoColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
