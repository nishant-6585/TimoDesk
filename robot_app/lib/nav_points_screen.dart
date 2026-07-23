import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart'; // kOrange
import 'nav_points_provider.dart';
import 'services/nav_points_api.dart';

// ── Theme tokens (match dashboard_screen.dart) ────────────────────────────────
const _bg = Color(0xFF0F0F0F);
const _panel = Color(0xFF151515);
const _panel2 = Color(0xFF1A1A1A);
const _line = Color(0xFF262626);
const _line2 = Color(0xFF2F2F2F);
const _ink = Color(0xFFF4F1EE);
const _muted = Color(0xFF9A9A9A);
const _muted2 = Color(0xFF6B6B6B);
const _info = Color(0xFF3B82F6);
const _red = Color(0xFFFF5247);
const _accent = kOrange;

/// On-robot Navigation Points: an operator drives Mikee to a spot, taps
/// "Capture point" to save its live SLAM pose to Supabase (SHARED with the web
/// admin), and one-taps "Go" to send the robot to any saved point. Big
/// tablet-friendly controls; dark theme + kOrange accents.
class NavPointsScreen extends ConsumerStatefulWidget {
  const NavPointsScreen({super.key});

  @override
  ConsumerState<NavPointsScreen> createState() => _NavPointsScreenState();
}

class _NavPointsScreenState extends ConsumerState<NavPointsScreen> {
  @override
  void initState() {
    super.initState();
    // Chassis control must be live for getPosition/navi; start it up front so
    // the first Capture/Go isn't a no-op (the provider also guards each call).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chassisProvider.notifier).startChassisControl();
    });
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: error ? const Color(0xFF2A1414) : _panel2,
        behavior: SnackBarBehavior.floating,
        content: Row(children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline,
              color: error ? _red : _accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
              child: Text(msg,
                  style: const TextStyle(color: _ink, fontSize: 15))),
        ]),
        duration: const Duration(seconds: 3),
      ));
  }

  Future<void> _onCapture() async {
    final result = await _promptName();
    if (result == null || result.$1.trim().isEmpty) return;
    final name = result.$1.trim();
    try {
      await ref
          .read(navPointsProvider.notifier)
          .capture(name, description: result.$2);
      _snack('Captured "$name"');
    } catch (e) {
      _snack(_clean(e), error: true);
    }
  }

  Future<void> _onEdit(NavPoint p) async {
    final result = await _promptName(
      title: 'Edit point',
      confirmLabel: 'Save',
      initialName: p.name,
      initialSay: p.description,
    );
    if (result == null || result.$1.trim().isEmpty) return;
    try {
      await ref
          .read(navPointsProvider.notifier)
          .update(p.id, name: result.$1.trim(), description: result.$2 ?? '');
      _snack('Updated "${result.$1.trim()}"');
    } catch (e) {
      _snack(_clean(e), error: true);
    }
  }

  Future<void> _onGoTo(NavPoint p) async {
    final ok = await ref.read(navPointsProvider.notifier).goTo(p);
    if (!ok) {
      _snack('Could not start navigation to "${p.name}"', error: true);
    } else {
      _snack('Going to "${p.name}"…');
    }
  }

  Future<void> _onCancelNav() async {
    await ref.read(navPointsProvider.notifier).cancel();
    _snack('Navigation cancelled');
  }

  Future<void> _onDelete(NavPoint p) async {
    final ok = await _confirmDelete(p);
    if (ok != true) return;
    try {
      await ref.read(navPointsProvider.notifier).delete(p.id);
      _snack('Deleted "${p.name}"');
    } catch (e) {
      _snack(_clean(e), error: true);
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(navPointsProvider);
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _topBar(),
          if (s.navigatingTo != null) _navBanner(s.navigatingTo!),
          if (s.navigatingTo == null && s.arrivedAt != null)
            _arrivedBanner(s.arrivedAt!),
          _captureBar(s.capturing),
          Expanded(
            child: s.points.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: _accent)),
              error: (e, _) => _errorState(_clean(e)),
              data: (list) =>
                  list.isEmpty ? _emptyState() : _list(list, s.navigatingTo),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────────
  Widget _topBar() {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: _panel2,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        _IconBox(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.of(context).pop()),
        const SizedBox(width: 14),
        const Icon(Icons.pin_drop_rounded, color: _accent, size: 24),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Navigation Points',
                  style: TextStyle(
                      color: _ink, fontSize: 18, fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Drive me somewhere, capture it, then send me back with one tap',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted2, fontSize: 12)),
            ],
          ),
        ),
        Consumer(builder: (_, ref, __) {
          final running = ref.watch(chassisProvider).isRunning;
          return _pill(running ? const Color(0xFF4ADE80) : Colors.white24,
              running ? 'Chassis Online' : 'Chassis Offline');
        }),
        const SizedBox(width: 8),
        // Map/localization readiness — go-to needs a loaded SLAM map + localization.
        Consumer(builder: (_, ref, __) {
          final ready = ref.watch(chassisProvider).isNaviReady;
          return _pill(ready ? const Color(0xFF4ADE80) : const Color(0xFFF59E0B),
              ready ? 'Map Ready' : 'No Map / Localizing');
        }),
        const SizedBox(width: 8),
        _IconBox(
            icon: Icons.refresh_rounded,
            onTap: () => ref.read(navPointsProvider.notifier).load()),
      ]),
    );
  }

  Widget _pill(Color dot, String label) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        border: Border.all(color: _line2),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                color: _ink, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Arrived banner (dismissible) ─────────────────────────────────────────────
  Widget _arrivedBanner(String name) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F1F14),
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, size: 22, color: Color(0xFF4ADE80)),
        const SizedBox(width: 14),
        Expanded(
          child: Text('Arrived at "$name"',
              style: const TextStyle(
                  color: _ink, fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        GestureDetector(
          onTap: () => ref.read(navPointsProvider.notifier).clearArrived(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border.all(color: _line2),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Text('Dismiss',
                style: TextStyle(
                    color: _muted, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  // ── Navigating banner (with Cancel) ──────────────────────────────────────────
  Widget _navBanner(NavPoint p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1412),
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(children: [
        const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: _accent)),
        const SizedBox(width: 14),
        Expanded(
          child: Text('Navigating to "${p.name}"…',
              style: const TextStyle(
                  color: _ink, fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        GestureDetector(
          onTap: _onCancelNav,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE5484D),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.stop_rounded, size: 20, color: Colors.white),
              SizedBox(width: 8),
              Text('Cancel',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Capture bar ──────────────────────────────────────────────────────────────
  Widget _captureBar(bool capturing) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF181818), Color(0xFF141414)]),
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('CAPTURE CURRENT POSITION',
                style: TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
            SizedBox(height: 6),
            Text('Drive me to a spot, then save my live SLAM pose under a name.',
                style: TextStyle(color: _muted2, fontSize: 13)),
          ]),
        ),
        const SizedBox(width: 16),
        SizedBox(
          height: 60,
          child: ElevatedButton.icon(
            onPressed: capturing ? null : _onCapture,
            icon: capturing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.add_location_alt_rounded, size: 24),
            label: Text(capturing ? 'Capturing…' : 'Capture point',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _panel2,
              disabledForegroundColor: _muted2,
              padding: const EdgeInsets.symmetric(horizontal: 26),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ]),
    );
  }

  // ── List ─────────────────────────────────────────────────────────────────────
  Widget _list(List<NavPoint> list, NavPoint? navigatingTo) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final p = list[i];
        return _PointTile(
          point: p,
          busy: navigatingTo != null,
          isTarget: navigatingTo?.id == p.id,
          onGoTo: () => _onGoTo(p),
          onEdit: () => _onEdit(p),
          onDelete: () => _onDelete(p),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.pin_drop_outlined, size: 64, color: _muted2),
          SizedBox(height: 16),
          Text('No saved points yet',
              style: TextStyle(
                  color: _muted, fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text('Drive me somewhere, then tap "Capture point".',
              style: TextStyle(color: _muted2, fontSize: 14)),
        ]),
      ),
    );
  }

  Widget _errorState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 56, color: _red),
          const SizedBox(height: 16),
          const Text('Could not load points',
              style: TextStyle(
                  color: _muted, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted2, fontSize: 13)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => ref.read(navPointsProvider.notifier).load(),
            icon: const Icon(Icons.refresh_rounded, size: 20, color: _accent),
            label: const Text('Retry',
                style: TextStyle(color: _accent, fontSize: 15)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _line2),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Name + announcement dialog ───────────────────────────────────────────────
  InputDecoration _dialogField(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _muted2, fontSize: 18),
        filled: true,
        fillColor: _bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _accent)),
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
        backgroundColor: _panel,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title,
            style: const TextStyle(
                color: _ink, fontSize: 20, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My current position will be saved under this name.',
                style: TextStyle(color: _muted, fontSize: 14)),
            const SizedBox(height: 18),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: const TextStyle(color: _ink, fontSize: 18),
              textCapitalization: TextCapitalization.words,
              decoration: _dialogField('e.g. Reception desk'),
            ),
            const SizedBox(height: 14),
            const Text('Arrival announcement (optional)',
                style: TextStyle(
                    color: _muted, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: sayCtrl,
              style: const TextStyle(color: _ink, fontSize: 16),
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  _dialogField("e.g. Welcome to Vishal's office"),
            ),
            const SizedBox(height: 6),
            const Text(
                'Spoken when I reach this point. Left empty, I\'ll say '
                '"We have arrived at <name>."',
                style: TextStyle(color: _muted2, fontSize: 12)),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
            child: const Text('Cancel',
                style: TextStyle(color: _muted, fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop((
              nameCtrl.text,
              sayCtrl.text.trim().isEmpty ? null : sayCtrl.text.trim(),
            )),
            style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: Text(confirmLabel,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(NavPoint p) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete point?',
            style: TextStyle(
                color: _ink, fontSize: 20, fontWeight: FontWeight.w700)),
        content: Text('Remove "${p.name}" permanently.',
            style: const TextStyle(color: _muted, fontSize: 15)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
            child: const Text('Cancel',
                style: TextStyle(color: _muted, fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE5484D),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: const Text('Delete',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Point tile ─────────────────────────────────────────────────────────────────
class _PointTile extends StatelessWidget {
  final NavPoint point;
  final bool busy; // a navigation is active (any point)
  final bool isTarget; // this is the point being navigated to
  final VoidCallback onGoTo;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _PointTile({
    required this.point,
    required this.busy,
    required this.isTarget,
    required this.onGoTo,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isWelcome = point.kind == 'welcome';
    final coords =
        'x ${point.x.toStringAsFixed(2)}  ·  y ${point.y.toStringAsFixed(2)}  ·  rot ${point.rotation.toStringAsFixed(1)}°';
    final markerColor = isWelcome ? _info : _accent;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF181818), Color(0xFF141414)]),
        border: Border.all(color: isTarget ? _accent : _line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: markerColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(isWelcome ? Icons.home_rounded : Icons.place_rounded,
              size: 26, color: markerColor),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(point.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (isWelcome) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: _info.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6)),
                      child: const Text('WELCOME',
                          style: TextStyle(
                              color: _info,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6)),
                    ),
                  ],
                ]),
                if (point.description != null &&
                    point.description!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(point.description!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 13)),
                ],
                const SizedBox(height: 6),
                Text(coords,
                    style: const TextStyle(
                        color: _muted2,
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ]),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            onPressed: busy ? null : onGoTo,
            icon: const Icon(Icons.navigation_rounded, size: 22),
            label: const Text('Go',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _panel2,
              disabledForegroundColor: _muted2,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13)),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 56,
          height: 56,
          child: IconButton(
            onPressed: busy ? null : onEdit,
            icon: const Icon(Icons.edit_outlined, size: 24),
            color: _muted2,
            tooltip: 'Edit',
          ),
        ),
        SizedBox(
          width: 56,
          height: 56,
          child: IconButton(
            onPressed: busy ? null : onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 26),
            color: _muted2,
            tooltip: 'Delete',
          ),
        ),
      ]),
    );
  }
}

// ── Top-bar icon box (matches dashboard) ─────────────────────────────────────────
class _IconBox extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBox({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(color: _line2),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: _muted),
        ),
      ),
    );
  }
}
