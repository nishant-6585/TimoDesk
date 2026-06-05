import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class SpineConnectionBanner extends StatelessWidget {
  final bool connected;

  const SpineConnectionBanner({
    Key? key,
    required this.connected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (connected) return const SizedBox.shrink();

    return AnimatedSlide(
      duration: const Duration(milliseconds: 300),
      offset: Offset(0, connected ? -1 : 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: TimoColors.warning.withOpacity(0.2),
          border: Border(
            bottom: BorderSide(color: TimoColors.warning.withOpacity(0.5)),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off,
              color: TimoColors.warning,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Spine disconnected — reconnecting...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TimoColors.warning,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
