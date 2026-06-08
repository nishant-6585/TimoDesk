import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';

const eventColorMap = {
  'command_drive': Color(0xFF3B82F6),
  'command_head': Color(0xFF3B82F6),
  'face_detected': Color(0xFF4ADE80),
  'visitor_checkin': Color(0xFF4ADE80),
  'safety_stop': Color(0xFFEF4444),
  'battery_low': Color(0xFFF59E0B),
  'snapshot_saved': Color(0xFFFF6B35),
  'admin_session': Color(0xFF6B7280),
};

class EventLogScreen extends ConsumerStatefulWidget {
  const EventLogScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<EventLogScreen> createState() => _EventLogScreenState();
}

class _EventLogScreenState extends ConsumerState<EventLogScreen> {
  String _filter = 'all';
  final List<Map<String, String>> _events = [
    {'time': 'just now', 'type': 'command_head', 'details': 'lr:45 ud:50', 'session': 'admin'},
    {'time': '2 sec ago', 'type': 'command_drive', 'details': 'dir: forward', 'session': 'admin'},
    {'time': '5 sec ago', 'type': 'face_detected', 'details': 'confidence: 87%', 'session': 'system'},
    {'time': '12 sec ago', 'type': 'safety_stop', 'details': 'triggered by admin', 'session': 'admin'},
  ];

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: TimoColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                height: 64,
                decoration: BoxDecoration(color: TimoColors.surface.withOpacity(0.8), border: const Border(bottom: BorderSide(color: TimoColors.border))),
                padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Row(children: [
                    Container(width: 36, height: 36, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [TimoColors.primary, TimoColors.primaryDark]), boxShadow: [BoxShadow(color: TimoColors.primary.withOpacity(0.35), blurRadius: 16)]), child: Center(child: Text('X', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)))),
                    if (!compact) ...[const SizedBox(width: 12), Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('TimoDesk', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: TimoColors.textPrimary, height: 1.0)), Text('xboom', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.15, color: TimoColors.textMuted, height: 1.0))])]
                  ]),
                  if (!compact) Text('Event Log', style: GoogleFonts.inter(fontSize: 13, color: TimoColors.textSecondary)),
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: TimoColors.success.withOpacity(0.08), border: Border.all(color: TimoColors.success.withOpacity(0.3)), borderRadius: BorderRadius.circular(8)), child: Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: TimoColors.success)), const SizedBox(width: 8), Text('ONLINE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: TimoColors.success))])),
                    const SizedBox(width: 12),
                    Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: TimoColors.border, width: 2), color: const Color(0xFF2A2A2A)), child: Center(child: Text('NK', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)))),
                  ]),
                ]),
              ),
              Expanded(
                child: Row(
                  children: [
                    if (!compact) _Sidebar(onNav: (route) {
                      final routes = {'dashboard': '/', 'control': '/control', 'feed': '/live-feed', 'gallery': '/gallery', 'events': '/event-log', 'settings': '/settings'};
                      if (routes.containsKey(route)) context.go(routes[route]!);
                    }),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1240),
                            child: Column(children: [
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [Icon(Icons.receipt_long, size: 28, color: TimoColors.primary), const SizedBox(width: 12), Text('Event Log', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold))]),
                                  const SizedBox(height: 4),
                                  Text('Full system + command audit trail', style: GoogleFonts.inter(fontSize: 13, color: TimoColors.textSecondary)),
                                ]),
                              ]),
                              const SizedBox(height: 24),
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                Row(children: [
                                  _FilterChip('all', _filter == 'all', () => setState(() => _filter = 'all')),
                                  const SizedBox(width: 8),
                                  _FilterChip('commands', _filter == 'commands', () => setState(() => _filter = 'commands')),
                                  const SizedBox(width: 8),
                                  _FilterChip('detections', _filter == 'detections', () => setState(() => _filter = 'detections')),
                                  const SizedBox(width: 8),
                                  _FilterChip('safety', _filter == 'safety', () => setState(() => _filter = 'safety')),
                                  const SizedBox(width: 8),
                                  _FilterChip('system', _filter == 'system', () => setState(() => _filter = 'system')),
                                ]),
                                Text('${_events.length} of ${_events.length}', style: GoogleFonts.inter(fontSize: 11, color: TimoColors.textMuted)),
                              ]),
                              const SizedBox(height: 20),
                              Container(
                                decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [TimoColors.cardTop, TimoColors.cardBottom]), border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(16)),
                                child: Column(children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                    child: Row(children: [
                                      SizedBox(width: 130, child: Text('TIME', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textMuted))),
                                      SizedBox(width: 210, child: Text('EVENT', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textMuted))),
                                      Expanded(child: Text('DETAILS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textMuted))),
                                      SizedBox(width: 150, child: Text('SESSION', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textMuted))),
                                    ]),
                                  ),
                                  Container(height: 1, color: TimoColors.border),
                                  ..._events.asMap().entries.map((e) => _EventRow(e.key, e.value)),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final Function(String) onNav;
  const _Sidebar({required this.onNav});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(color: TimoColors.surface, border: const Border(right: BorderSide(color: TimoColors.border))),
      child: Column(children: [Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [
        _NavItem('Dashboard', Icons.space_dashboard, false, () => onNav('dashboard')),
        _NavItem('Control', Icons.sports_esports, false, () => onNav('control')),
        _NavItem('Live Feed', Icons.videocam, false, () => onNav('feed')),
        _NavItem('Gallery', Icons.photo_library, false, () => onNav('gallery')),
        _NavItem('Event Log', Icons.receipt_long, true, () => onNav('events')),
        _NavItem('Settings', Icons.settings, false, () => onNav('settings')),
      ]))]),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _NavItem(this.label, this.icon, this.active, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: active ? TimoColors.primary.withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [if (active) Container(width: 4, height: 20, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: TimoColors.primary, borderRadius: BorderRadius.circular(999))), Icon(icon, size: 20, color: active ? TimoColors.primary : TimoColors.textSecondary), const SizedBox(width: 12), Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: active ? FontWeight.w500 : FontWeight.normal, color: active ? TimoColors.primary : TimoColors.textSecondary)))]),
    ))));
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip(this.label, this.active, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: active ? TimoColors.primary.withOpacity(0.15) : Colors.transparent, border: Border.all(color: active ? TimoColors.primary : TimoColors.border), borderRadius: BorderRadius.circular(20)), child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: active ? TimoColors.primary : TimoColors.textSecondary)))));
  }
}

class _EventRow extends StatelessWidget {
  final int idx;
  final Map<String, String> event;
  const _EventRow(this.idx, this.event);
  @override
  Widget build(BuildContext context) {
    final color = eventColorMap[event['type']] ?? TimoColors.textMuted;
    return Container(
      color: idx % 2 == 1 ? Colors.white.withOpacity(0.012) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(children: [
        SizedBox(width: 130, child: Text(event['time']!, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: TimoColors.textSecondary))),
        SizedBox(width: 210, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.12), border: Border.all(color: color.withOpacity(0.25)), borderRadius: BorderRadius.circular(6)), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)), const SizedBox(width: 6), Text(event['type']!, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500, color: color))]))),
        Expanded(child: Text(event['details']!, style: GoogleFonts.jetBrainsMono(fontSize: 13, color: Colors.white.withOpacity(0.85)))),
        SizedBox(width: 150, child: Row(children: [Icon(event['session'] == 'admin' ? Icons.person : Icons.memory, size: 14, color: TimoColors.textSecondary), const SizedBox(width: 6), Text(event['session']!, style: GoogleFonts.inter(fontSize: 12, color: TimoColors.textSecondary))])),
      ]),
    );
  }
}
