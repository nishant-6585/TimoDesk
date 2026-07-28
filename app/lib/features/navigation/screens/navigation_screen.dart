import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../services/spine/navi_status_provider.dart';
import '../../../services/spine/spine_provider.dart';
import '../providers/nav_points_provider.dart';
import '../widgets/escort_panel.dart';

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
  bool _patrolling = false;

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
    final result = await _promptName();
    if (result == null || result.$1.trim().isEmpty) return;
    final name = result.$1.trim();

    setState(() => _capturing = true);
    try {
      await ref
          .read(navPointsProvider.notifier)
          .capture(name, description: result.$2);
      _snack('Captured "$name"');
    } catch (e) {
      _snack('Capture failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  InputDecoration _dialogField(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(fontSize: 14, color: MikeeColors.textMuted),
        filled: true,
        fillColor: MikeeColors.inset,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: MikeeColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: MikeeColors.primary)),
      );

  /// Returns (name, arrivalAnnouncement) — announcement null when left empty.
  Future<(String, String?)?> _promptName({
    String title = 'Name this point',
    String confirmLabel = 'Capture',
    String? initialName,
    String? initialSay,
  }) {
    final nameCtrl = TextEditingController(text: initialName ?? '');
    final sayCtrl = TextEditingController(text: initialSay ?? '');
    return showDialog<(String, String?)>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MikeeColors.cardTop,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('The robot\'s current position will be saved under this name.',
              style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
          const SizedBox(height: 16),
          TextField(
            controller: nameCtrl,
            autofocus: true,
            style: GoogleFonts.inter(fontSize: 14, color: MikeeColors.textPrimary),
            decoration: _dialogField('e.g. Reception desk'),
          ),
          const SizedBox(height: 14),
          Text('ARRIVAL ANNOUNCEMENT (OPTIONAL)',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.08, color: MikeeColors.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: sayCtrl,
            style: GoogleFonts.inter(fontSize: 14, color: MikeeColors.textPrimary),
            decoration: _dialogField("e.g. Welcome to Vishal's office"),
          ),
          const SizedBox(height: 6),
          Text('The robot speaks this on reaching the point. Left empty it says "We have arrived at <name>."',
              style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: GoogleFonts.inter(color: MikeeColors.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop((
              nameCtrl.text,
              sayCtrl.text.trim().isEmpty ? null : sayCtrl.text.trim(),
            )),
            style: ElevatedButton.styleFrom(backgroundColor: MikeeColors.primary, foregroundColor: Colors.white),
            child: Text(confirmLabel, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _onEdit(NavPoint point) async {
    final result = await _promptName(
      title: 'Edit point',
      confirmLabel: 'Save',
      initialName: point.name,
      initialSay: point.description,
    );
    if (result == null || result.$1.trim().isEmpty) return;
    try {
      await ref
          .read(navPointsProvider.notifier)
          .update(point.id, name: result.$1.trim(), description: result.$2 ?? '');
      _snack('Updated "${result.$1.trim()}"');
    } catch (e) {
      _snack('Update failed: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  void _onGoTo(NavPoint point) {
    if (!_robotOnline) {
      _snack('Robot offline — cannot navigate');
      return;
    }
    ref.read(navPointsProvider.notifier).goTo(point);
    _snack('Sending robot to "${point.name}"…');
  }

  void _onPatrolToggle(List<NavPoint> points) {
    if (_patrolling) {
      ref.read(navPointsProvider.notifier).patrolStop();
      _snack('Patrol stopped');
    } else {
      if (points.length < 2) {
        _snack('Need at least 2 saved points to patrol');
        return;
      }
      ref.read(navPointsProvider.notifier).patrolStart(points);
      _snack('Patrol started — looping ${points.length} points');
    }
    setState(() => _patrolling = !_patrolling);
  }

  void _onCancelNavi() {
    ref.read(navPointsProvider.notifier).cancelNavi();
    _snack('Cancelling navigation…');
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
    final naviStatus = ref.watch(naviStatusProvider);

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
            const SizedBox(height: 12),
            Row(children: [
              const Spacer(),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: online
                      ? () => _onPatrolToggle(pointsAsync.valueOrNull ?? const [])
                      : null,
                  icon: Icon(_patrolling ? Icons.stop : Icons.route, size: 16),
                  label: Text(_patrolling ? 'Stop patrol' : 'Patrol all points',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _patrolling ? MikeeColors.error : MikeeColors.cardTop,
                    foregroundColor: _patrolling ? Colors.white : MikeeColors.textPrimary,
                    side: _patrolling ? null : const BorderSide(color: MikeeColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
            if (naviStatus != null) ...[
              const SizedBox(height: 16),
              _NavigatingBanner(
                status: naviStatus,
                onCancel: _onCancelNavi,
                onDismiss: () => ref.read(naviStatusProvider.notifier).clear(),
              ),
            ],
            const SizedBox(height: 16),
            EscortPanel(online: online),
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
                                  onEdit: () => _onEdit(p),
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

/// Shown while a Go To is in flight. Persists until the robot confirms a
/// cancel (cancel_result clears the provider) or the user dismisses it, so the
/// Cancel button stays reachable for the whole navigation.
class _NavigatingBanner extends StatelessWidget {
  final NaviStatus status;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;
  const _NavigatingBanner({required this.status, required this.onCancel, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final accent = status.arrived ? MikeeColors.success : MikeeColors.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        border: Border.all(color: accent.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        if (status.arrived)
          const Icon(Icons.check_circle, size: 20, color: MikeeColors.success)
        else
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: MikeeColors.primary),
          ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              status.arrived
                  ? 'Arrived at "${status.pointName}"'
                  : status.cancelling
                      ? 'Cancelling navigation…'
                      : 'Navigating to "${status.pointName}"',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: MikeeColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              status.arrived
                  ? 'Navigation complete.'
                  : status.cancelling
                      ? 'Waiting for the robot to confirm the cancel.'
                      : status.stalled
                          ? 'Robot is NOT moving — its navigation service looks wedged. '
                              'Cancel, then power-cycle the robot if this repeats.'
                          : 'The robot is driving autonomously to the saved point.',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: status.stalled ? MikeeColors.error : MikeeColors.textSecondary,
                  fontWeight: status.stalled ? FontWeight.w600 : FontWeight.w400),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        if (!status.arrived)
          SizedBox(
            height: 38,
            child: ElevatedButton.icon(
              onPressed: status.cancelling ? null : onCancel,
              icon: const Icon(Icons.close, size: 16),
              label: Text('Cancel navigation', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: MikeeColors.error,
                foregroundColor: Colors.white,
                disabledBackgroundColor: MikeeColors.inset,
                disabledForegroundColor: MikeeColors.textMuted,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        IconButton(
          onPressed: onDismiss,
          icon: Icon(status.arrived ? Icons.close : Icons.visibility_off_outlined, size: 18),
          color: MikeeColors.textMuted,
          tooltip: status.arrived ? 'Dismiss' : 'Hide banner (does not stop the robot)',
        ),
      ]),
    );
  }
}

class _PointTile extends StatelessWidget {
  final NavPoint point;
  final bool online;
  final VoidCallback onGoTo;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _PointTile({required this.point, required this.online, required this.onGoTo, required this.onEdit, required this.onDelete});

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
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 19),
          color: MikeeColors.textMuted,
          tooltip: 'Edit name & announcement',
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
