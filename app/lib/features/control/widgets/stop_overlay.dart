import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class StopOverlay extends StatelessWidget {
  final bool visible;
  final VoidCallback onResume;

  const StopOverlay({
    Key? key,
    required this.visible,
    required this.onResume,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.stop_circle,
              color: MikeeColors.error,
              size: 64,
            ),
            const SizedBox(height: 24),
            Text(
              'SYSTEM STOPPED',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: MikeeColors.error,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: onResume,
              style: ElevatedButton.styleFrom(
                backgroundColor: MikeeColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('RESUME'),
            ),
          ],
        ),
      ),
    );
  }
}
