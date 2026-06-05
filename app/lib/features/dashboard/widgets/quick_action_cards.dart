import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';

class QuickActionCards extends StatelessWidget {
  const QuickActionCards({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 1,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _ActionCard(
          icon: Icons.videogame_asset,
          label: 'Control',
          onTap: () => context.go('/control'),
        ),
        _ActionCard(
          icon: Icons.videocam,
          label: 'Live Feed',
          onTap: () => context.go('/live-feed'),
        ),
        _ActionCard(
          icon: Icons.image,
          label: 'Gallery',
          onTap: () => context.go('/gallery'),
        ),
        _ActionCard(
          icon: Icons.event_note,
          label: 'Event Log',
          onTap: () => context.go('/events'),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: TimoColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: TimoColors.primary,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: TimoColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
