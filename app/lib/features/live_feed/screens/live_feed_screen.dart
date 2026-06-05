import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../services/spine/spine_provider.dart';

class LiveFeedScreen extends ConsumerWidget {
  const LiveFeedScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spineState = ref.watch(spineProvider);

    // For now, use a test image. In production, use robot IP from settings
    const mjpegUrl = 'http://192.168.10.18:8080/stream';

    return Scaffold(
      backgroundColor: TimoColors.background,
      body: Stack(
        children: [
          // MJPEG stream (placeholder: show color background)
          Container(
            color: Colors.black,
            child: Center(
              child: Image.network(
                mjpegUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.videocam_off,
                            color: TimoColors.textSecondary,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'MJPEG Stream Unavailable',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: TimoColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Check robot IP in settings',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: TimoColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12) +
                  EdgeInsets.only(top: MediaQuery.of(context).padding.top),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: spineState.connected ? TimoColors.success.withOpacity(0.8) : TimoColors.error.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          spineState.connected ? Icons.cloud_done : Icons.cloud_off,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          spineState.connected ? 'Connected' : 'Offline',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // STOP button (floating)
          Positioned(
            top: 100,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: TimoColors.error,
              onPressed: () => ref.read(spineProvider.notifier).sendIntent({'intent': 'stop'}),
              child: const Icon(Icons.stop, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
