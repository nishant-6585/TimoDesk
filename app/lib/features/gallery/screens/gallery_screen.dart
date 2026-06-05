import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  final String? detailId;

  const GalleryScreen({Key? key, this.detailId}) : super(key: key);

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  bool _isRefreshing = false;

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    // If detailId is provided, show full-screen view
    if (widget.detailId != null) {
      return _FullScreenView(captureId: widget.detailId!);
    }

    return Scaffold(
      backgroundColor: TimoColors.background,
      appBar: AppBar(
        title: const Text('Gallery'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        backgroundColor: TimoColors.surface,
        color: TimoColors.primary,
        child: StreamBuilder(
          stream: Supabase.instance.client
              .from('capture')
              .stream(primaryKey: ['id'])
              .order('taken_at', ascending: false),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Error: ${snapshot.error}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TimoColors.error,
                  ),
                ),
              );
            }

            final captures = snapshot.data ?? [];

            if (captures.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.image_not_supported,
                      color: TimoColors.textSecondary,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No captures yet',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: TimoColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: captures.length,
              itemBuilder: (context, index) {
                final capture = captures[index];
                return _CaptureCard(capture: capture);
              },
            );
          },
        ),
      ),
    );
  }
}

class _CaptureCard extends ConsumerWidget {
  final Map<String, dynamic> capture;

  const _CaptureCard({required this.capture});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storageUrl = capture['storage_url'] ?? '';
    final kind = capture['kind'] ?? 'unknown';
    final takenAt = capture['taken_at'] != null
        ? DateTime.parse(capture['taken_at']).toLocal()
        : DateTime.now();
    final timeAgo = _formatTimeAgo(takenAt);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go('/gallery/${capture['id']}'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: TimoColors.border),
            borderRadius: BorderRadius.circular(12),
            color: TimoColors.surface,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Fix 3: Use storage_url directly with CachedNetworkImage
              CachedNetworkImage(
                imageUrl: storageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(strokeWidth: 1),
                ),
                errorWidget: (context, url, error) => Container(
                  color: TimoColors.border,
                  child: const Icon(Icons.image_not_supported, color: TimoColors.textSecondary),
                ),
                memCacheHeight: 200, // Prevent loading full-res in grid
              ),

              // Gradient overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                ),
              ),

              // Info at bottom
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getKindColor(kind).withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        kind,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeAgo,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getKindColor(String kind) {
    switch (kind) {
      case 'admin_snapshot':
        return TimoColors.primary;
      case 'intrusion':
        return TimoColors.error;
      case 'patrol':
        return TimoColors.success;
      default:
        return TimoColors.textSecondary;
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}

class _FullScreenView extends ConsumerWidget {
  final String captureId;

  const _FullScreenView({required this.captureId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: Supabase.instance.client
          .from('capture')
          .select()
          .eq('id', captureId)
          .single(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Text(
                'Error loading image',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white),
              ),
            ),
          );
        }

        final capture = snapshot.data!;
        final storageUrl = capture['storage_url'] ?? '';

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.pop(),
            ),
          ),
          body: Center(
            child: CachedNetworkImage(
              imageUrl: storageUrl,
              fit: BoxFit.contain,
              progressIndicatorBuilder: (context, url, progress) => Center(
                child: CircularProgressIndicator(value: progress.progress),
              ),
              errorWidget: (context, url, error) => const Icon(
                Icons.image_not_supported,
                color: TimoColors.textSecondary,
                size: 64,
              ),
            ),
          ),
        );
      },
    );
  }
}
