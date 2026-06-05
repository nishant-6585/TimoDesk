import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme.dart';

final _eventFilterProvider = StateProvider<String>((ref) => 'all');

class EventLogScreen extends ConsumerStatefulWidget {
  const EventLogScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<EventLogScreen> createState() => _EventLogScreenState();
}

class _EventLogScreenState extends ConsumerState<EventLogScreen> {
  Future<void> _refresh() async {
    // Supabase stream automatically refreshes
    await Future.delayed(const Duration(seconds: 1));
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(_eventFilterProvider);

    return Scaffold(
      backgroundColor: TimoColors.background,
      appBar: AppBar(
        title: const Text('Event Log'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Column(
        children: [
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: filter == 'all',
                  onSelected: () => ref.read(_eventFilterProvider.notifier).state = 'all',
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Movement',
                  selected: filter == 'movement',
                  onSelected: () => ref.read(_eventFilterProvider.notifier).state = 'movement',
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Safety',
                  selected: filter == 'safety',
                  onSelected: () => ref.read(_eventFilterProvider.notifier).state = 'safety',
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'System',
                  selected: filter == 'system',
                  onSelected: () => ref.read(_eventFilterProvider.notifier).state = 'system',
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              backgroundColor: TimoColors.surface,
              color: TimoColors.primary,
              child: StreamBuilder(
                stream: Supabase.instance.client
                    .from('robot_event')
                    .stream(primaryKey: ['id'])
                    .order('occurred_at', ascending: false)
                    .limit(100),
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

                  var events = snapshot.data ?? [];

                  // Filter events
                  if (filter != 'all') {
                    events = events.where((e) => _matchesFilter(e['type'], filter)).toList();
                  }

                  if (events.isEmpty) {
                    return Center(
                      child: Text(
                        'No events',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TimoColors.textSecondary,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return _EventRow(event: event);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesFilter(String type, String filter) {
    switch (filter) {
      case 'movement':
        return type.contains('drive') || type.contains('head') || type.contains('arm');
      case 'safety':
        return type.contains('stop') || type.contains('resume');
      case 'system':
        return type.contains('battery') || type.contains('connection') || type.contains('session');
      default:
        return true;
    }
  }
}

class _EventRow extends StatelessWidget {
  final Map<String, dynamic> event;

  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final type = event['type'] ?? 'unknown';
    final payload = event['payload'] ?? {};
    final occurredAt = event['occurred_at'] != null
        ? DateTime.parse(event['occurred_at']).toLocal()
        : DateTime.now();
    final timeAgo = _formatTimeAgo(occurredAt);

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: TimoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TimoColors.border),
      ),
      child: Row(
        children: [
          // Type indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getTypeColor(type).withOpacity(0.2),
              border: Border.all(color: _getTypeColor(type)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              type,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _getTypeColor(type),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Payload summary
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (payload.isNotEmpty)
                  Text(
                    _formatPayload(payload),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TimoColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  timeAgo,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: TimoColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(String type) {
    if (type.contains('stop')) return TimoColors.error;
    if (type.contains('resume')) return TimoColors.success;
    if (type.contains('command')) return TimoColors.primary;
    if (type.contains('face')) return TimoColors.success;
    if (type.contains('battery')) return TimoColors.warning;
    return TimoColors.textSecondary;
  }

  String _formatPayload(Map<String, dynamic> payload) {
    if (payload.isEmpty) return '—';
    final entries = payload.entries.take(2).map((e) => '${e.key}: ${e.value}').toList();
    return entries.join(', ');
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? TimoColors.primary : Colors.transparent,
            border: Border.all(
              color: selected ? TimoColors.primary : TimoColors.border,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: selected ? Colors.black : TimoColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
