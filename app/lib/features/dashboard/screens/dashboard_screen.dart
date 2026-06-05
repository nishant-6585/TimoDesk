import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme.dart';
import '../../../services/spine/spine_provider.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../widgets/robot_status_chip.dart';
import '../widgets/spine_connection_banner.dart';
import '../widgets/quick_action_cards.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spineState = ref.watch(spineProvider);

    return Scaffold(
      backgroundColor: TimoColors.background,
      appBar: AppBar(
        title: const Text('TimoDesk'),
        elevation: 1,
        actions: [
          if (spineState.status != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RobotStatusChip(
                online: spineState.status!.online,
                battery: spineState.status!.battery,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              context.go('/login');
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Spine connection banner
            SpineConnectionBanner(connected: spineState.connected),
            const SizedBox(height: 24),

            // Quick action cards
            const QuickActionCards(),
            const SizedBox(height: 32),

            // Recent events section
            Text(
              'Recent Events',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: TimoColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            // Event list placeholder
            _RecentEventsList(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ref.read(spineProvider.notifier).sendIntent({'intent': 'stop'});
        },
        backgroundColor: TimoColors.error,
        child: const Icon(Icons.stop, color: Colors.white),
        tooltip: 'Emergency STOP',
      ),
    );
  }
}

class _RecentEventsList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder(
      stream: Supabase.instance.client
          .from('robot_event')
          .stream(primaryKey: ['id'])
          .order('occurred_at', ascending: false)
          .limit(3),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TimoColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: TimoColors.border),
            ),
            child: Text(
              'Error loading events: ${snapshot.error}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TimoColors.error,
              ),
            ),
          );
        }

        final events = snapshot.data ?? [];

        if (events.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TimoColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: TimoColors.border),
            ),
            child: Center(
              child: Text(
                'No events yet',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TimoColors.textSecondary,
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            final type = event['type'] ?? 'unknown';

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
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _getEventColor(type),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: TimoColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (event['payload'] != null)
                          Text(
                            event['payload'].toString().substring(0, 40),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: TimoColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Color _getEventColor(String type) {
    if (type.contains('stop')) return TimoColors.error;
    if (type.contains('command')) return TimoColors.primary;
    if (type.contains('face')) return TimoColors.success;
    if (type.contains('battery')) return TimoColors.warning;
    return TimoColors.textSecondary;
  }
}
