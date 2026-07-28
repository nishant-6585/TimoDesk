import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../services/spine/escort_status_provider.dart';
import '../providers/nav_points_provider.dart';

/// Follow-Me escort panel for the Navigation screen.
///
/// Idle: tap saved points to build an ordered route, then Start escort — the
/// spine walks the route but pauses every ~2m and at each waypoint to verify
/// the visitor is still following (camera person-check); nobody within the
/// timeout stops the robot in place.
///
/// Active: shows live progress from the spine's navi_state escort field
/// (cross-client — an escort started on the robot shows here too) + Stop.
class EscortPanel extends ConsumerStatefulWidget {
  final bool online;
  const EscortPanel({Key? key, required this.online}) : super(key: key);

  @override
  ConsumerState<EscortPanel> createState() => _EscortPanelState();
}

class _EscortPanelState extends ConsumerState<EscortPanel> {
  final List<NavPoint> _route = [];

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: GoogleFonts.inter(fontSize: 13))),
    );
  }

  void _start() {
    if (_route.isEmpty) return;
    ref.read(navPointsProvider.notifier).escortStart(_route);
    _snack('Escort started — ${_route.length} waypoint(s), person-verified');
  }

  void _stop() {
    ref.read(navPointsProvider.notifier).escortStop();
    _snack('Escort stopped');
  }

  @override
  Widget build(BuildContext context) {
    final escort = ref.watch(escortStatusProvider);
    final points = ref.watch(navPointsProvider).valueOrNull ?? const <NavPoint>[];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [MikeeColors.cardTop, MikeeColors.cardBottom]),
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.directions_walk, size: 18, color: MikeeColors.primary),
          const SizedBox(width: 8),
          Text('ESCORT MODE — FOLLOW ME',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.12,
                  color: MikeeColors.textSecondary)),
        ]),
        const SizedBox(height: 6),
        Text(
          'Walks the route below, but checks a visitor is still following '
          '(camera scan) every ~2m and at each waypoint — stops if nobody is there.',
          style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textMuted),
        ),
        const SizedBox(height: 14),
        if (escort != null) _activeView(escort) else _builderView(points),
      ]),
    );
  }

  // ── Active escort: live progress + stop ────────────────────────────────────
  Widget _activeView(EscortStatus escort) {
    final checking = escort.checking;
    final accent = checking ? MikeeColors.warning : MikeeColors.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        border: Border.all(color: accent.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        if (checking)
          const Icon(Icons.person_search, size: 20, color: MikeeColors.warning)
        else
          const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: MikeeColors.primary)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Escorting — waypoint ${escort.index + 1} of ${escort.total}',
              style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: MikeeColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              checking
                  ? 'Paused — scanning for the visitor…'
                  : 'Walking with person checks every ~2m.',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: checking
                      ? MikeeColors.warning
                      : MikeeColors.textSecondary),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 38,
          child: ElevatedButton.icon(
            onPressed: _stop,
            icon: const Icon(Icons.stop, size: 16),
            label: Text('Stop escort',
                style:
                    GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: MikeeColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Idle: build the route from saved points, then start ────────────────────
  Widget _builderView(List<NavPoint> points) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (points.isEmpty)
        Text('Capture at least one point above to build an escort route.',
            style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textMuted))
      else ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in points)
            ActionChip(
              avatar: const Icon(Icons.add, size: 15, color: MikeeColors.primary),
              label: Text(p.name,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: MikeeColors.textPrimary)),
              backgroundColor: MikeeColors.inset,
              side: const BorderSide(color: MikeeColors.border),
              onPressed: () {
                // Repeats are fine (out-and-back routes), just not back-to-back.
                if (_route.isNotEmpty && _route.last.id == p.id) {
                  _snack('"${p.name}" is already the last stop');
                  return;
                }
                setState(() => _route.add(p));
              },
            ),
        ]),
        if (_route.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('ROUTE (IN ORDER — LAST IS THE DESTINATION)',
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  color: MikeeColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < _route.length; i++)
              InputChip(
                avatar: CircleAvatar(
                  backgroundColor: MikeeColors.primary.withOpacity(0.2),
                  child: Text('${i + 1}',
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: MikeeColors.primary)),
                ),
                label: Text(_route[i].name,
                    style: GoogleFonts.inter(
                        fontSize: 12, color: MikeeColors.textPrimary)),
                backgroundColor: MikeeColors.inset,
                side: const BorderSide(color: MikeeColors.border),
                deleteIconColor: MikeeColors.textMuted,
                onDeleted: () => setState(() => _route.removeAt(i)),
              ),
          ]),
        ],
        const SizedBox(height: 14),
        Row(children: [
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: (widget.online && _route.isNotEmpty) ? _start : null,
              icon: const Icon(Icons.directions_walk, size: 16),
              label: Text('Start escort',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: MikeeColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: MikeeColors.inset,
                disabledForegroundColor: MikeeColors.textMuted,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (_route.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _route.clear()),
              child: Text('Clear route',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: MikeeColors.textSecondary)),
            ),
          const Spacer(),
          if (!widget.online)
            Text('Robot offline',
                style:
                    GoogleFonts.inter(fontSize: 12, color: MikeeColors.error)),
        ]),
      ],
    ]);
  }
}
