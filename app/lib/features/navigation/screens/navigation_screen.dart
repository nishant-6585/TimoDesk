import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../services/spine/spine_provider.dart';
import '../providers/nav_points_provider.dart';

/// Navigation Points: capture named SLAM poses by driving the robot, then
/// one-tap "send robot to <point>". Body-only — AppShell supplies header+sidebar
/// (same pattern as ControlScreen).
class NavigationScreen extends ConsumerStatefulWidget {
  const NavigationScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  bool _capturing = false;

  bool get _robotOnline {
    final spine = ref.read(spineProvider);
    return spine.connected && (spine.status?.online ?? false);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: GoogleFonts.inter(fontSize: 13))),
    );
  }

  Future<void> _onCapture() async {
    if (!_robotOnline) {
      _snack('Robot offline — cannot capture position');
      return;
    }
    final name = await _promptName();
    if (name == null || name.trim().isEmpty) return;

    setState(() => _capturing = true);
    try {
      await ref.read(navPointsProvider.notifier).capture(name.trim());
      _snack('Captured "${name.trim()}"');
    } catch (e) {
      _snack('Capture failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<String?> _promptName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MikeeColors.cardTop,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Name this point', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('The robot\'s current position will be saved under this name.',
              style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            style: GoogleFonts.inter(fontSize: 14, color: MikeeColors.textPrimary),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
            decoration: InputDecoration(
              hintText: 'e.g. Reception desk',
              hintStyle: GoogleFonts.inter(fontSize: 14, color: MikeeColors.textMuted),
              filled: true,
              fillColor: MikeeColors.inset,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: MikeeColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: MikeeColors.primary)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: GoogleFonts.inter(color: MikeeColors.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            style: ElevatedButton.styleFrom(backgroundColor: MikeeColors.primary, foregroundColor: Colors.white),
            child: Text('Capture', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _onGoTo(NavPoint point) {
    if (!_robotOnline) {
      _snack('Robot offline — cannot navigate');
      return;
    }
    ref.read(navPointsProvider.notifier).goTo(point);
    _snack('Sending robot to "${point.name}"…');
  }

  Future<void> _onDelete(NavPoint point) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MikeeColors.cardTop,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete point?', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600)),
        content: Text('Remove "${point.name}" permanently.', style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Cancel', style: GoogleFonts.inter(color: MikeeColors.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: MikeeColors.error, foregroundColor: Colors.white),
            child: Text('Delete', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(navPointsProvider.notifier).delete(point.id);
      _snack('Deleted "${point.name}"');
    } catch (e) {
      _snack('Delete failed: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final spine = ref.watch(spineProvider);
    final online = spine.connected && (spine.status?.online ?? false);
    final pointsAsync = ref.watch(navPointsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Header(online: online),
            const SizedBox(height: 24),
            _CaptureBar(
              online: online,
              capturing: _capturing,
              onCapture: _onCapture,
            ),
            const SizedBox(height: 24),
            pointsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator(color: MikeeColors.primary)),
              ),
              error: (e, _) => _ErrorState(message: e.toString(), onRetry: () => ref.read(navPointsProvider.notifier).load()),
              data: (points) => points.isEmpty
                  ? const _EmptyState()
                  : Column(
                      children: points
                          .map((p) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _PointTile(
                                  point: p,
                                  online: online,
                                  onGoTo: () => _onGoTo(p),
                                  onDelete: () => _onDelete(p),
                                ),
                              ))
                          .toList(),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool online;
  const _Header({required this.online});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(Icons.pin_drop, size: 28, color: MikeeColors.primary),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Navigation Points', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Drive the robot to a spot, capture it, then send the robot back with one tap',
              style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
        ]),
      ),
      if (!online)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: MikeeColors.error.withOpacity(0.08),
            border: Border.all(color: MikeeColors.error.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('ROBOT OFFLINE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: MikeeColors.error, letterSpacing: 0.05)),
        ),
    ]);
  }
}

class _CaptureBar extends StatelessWidget {
  final bool online;
  final bool capturing;
  final VoidCallback onCapture;
  const _CaptureBar({required this.online, required this.capturing, required this.onCapture});
  @override
  Widget build(BuildContext context) {
    final enabled = online && !capturing;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]),
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CAPTURE CURRENT POSITION', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
            const SizedBox(height: 6),
            Text(
              online ? 'Saves the robot\'s live SLAM pose under a name you choose.' : 'Connect the robot to capture its position.',
              style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textMuted),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: enabled ? onCapture : null,
            icon: capturing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_location_alt, size: 18),
            label: Text(capturing ? 'Capturing…' : 'Capture point', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: MikeeColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: MikeeColors.inset,
              disabledForegroundColor: MikeeColors.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _PointTile extends StatelessWidget {
  final NavPoint point;
  final bool online;
  final VoidCallback onGoTo;
  final VoidCallback onDelete;
  const _PointTile({required this.point, required this.online, required this.onGoTo, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isWelcome = point.kind == 'welcome';
    final coords =
        'x ${point.x.toStringAsFixed(2)} · y ${point.y.toStringAsFixed(2)} · rot ${point.rotation.toStringAsFixed(1)}°';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]),
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (isWelcome ? MikeeColors.info : MikeeColors.primary).withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(isWelcome ? Icons.home : Icons.place, size: 20, color: isWelcome ? MikeeColors.info : MikeeColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(point.name, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: MikeeColors.textPrimary))),
              if (isWelcome) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: MikeeColors.info.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                  child: Text('WELCOME', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: MikeeColors.info, letterSpacing: 0.1)),
                ),
              ],
            ]),
            if (point.description != null && point.description!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(point.description!, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textSecondary)),
            ],
            const SizedBox(height: 4),
            Text(coords, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: MikeeColors.textMuted)),
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 38,
          child: ElevatedButton.icon(
            onPressed: online ? onGoTo : null,
            icon: const Icon(Icons.navigation, size: 16),
            label: Text('Go to', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: MikeeColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: MikeeColors.inset,
              disabledForegroundColor: MikeeColors.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: 20),
          color: MikeeColors.textMuted,
          tooltip: 'Delete',
        ),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Icon(Icons.pin_drop_outlined, size: 48, color: MikeeColors.textMuted),
        const SizedBox(height: 12),
        Text('No saved points yet', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: MikeeColors.textSecondary)),
        const SizedBox(height: 4),
        Text('Drive the robot somewhere, then tap “Capture point”.', style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textMuted)),
      ]),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        border: Border.all(color: MikeeColors.error.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Icon(Icons.error_outline, size: 40, color: MikeeColors.error),
        const SizedBox(height: 12),
        Text('Could not load points', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: MikeeColors.textSecondary)),
        const SizedBox(height: 4),
        Text(message.replaceFirst('Exception: ', ''), textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textMuted)),
        const SizedBox(height: 16),
        TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 16), label: Text('Retry', style: GoogleFonts.inter(fontSize: 13))),
      ]),
    );
  }
}
