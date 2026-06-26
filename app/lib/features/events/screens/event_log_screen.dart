import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../services/spine/face_detection_provider.dart';

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
    {'time': 'just now', 'type': 'command_head', 'details': 'lr:50 ud:50', 'session': 'admin'},
    {'time': '2 sec ago', 'type': 'command_drive', 'details': 'dir: forward', 'session': 'admin'},
    {'time': '12 sec ago', 'type': 'safety_stop', 'details': 'triggered_by: admin', 'session': 'admin'},
    {'time': '15 sec ago', 'type': 'command_head', 'details': 'lr:37 ud:57', 'session': 'admin'},
    {'time': '18 sec ago', 'type': 'command_drive', 'details': 'dir: left', 'session': 'admin'},
    {'time': '20 sec ago', 'type': 'visitor_checkin', 'details': 'guest #168', 'session': 'system'},
    {'time': '25 sec ago', 'type': 'command_head', 'details': 'lr:50 ud:49', 'session': 'admin'},
    {'time': '28 sec ago', 'type': 'command_head', 'details': 'lr:37 ud:54', 'session': 'admin'},
    {'time': '30 sec ago', 'type': 'command_drive', 'details': 'dir: left', 'session': 'admin'},
    {'time': '35 sec ago', 'type': 'visitor_checkin', 'details': 'guest #188', 'session': 'system'},
    {'time': '38 sec ago', 'type': 'visitor_checkin', 'details': 'guest #114', 'session': 'system'},
    {'time': '40 sec ago', 'type': 'visitor_checkin', 'details': 'guest #177', 'session': 'system'},
    {'time': '42 sec ago', 'type': 'visitor_checkin', 'details': 'guest #161', 'session': 'system'},
    {'time': '45 sec ago', 'type': 'command_head', 'details': 'lr:44 ud:40', 'session': 'admin'},
    {'time': '48 sec ago', 'type': 'command_drive', 'details': 'dir: forward', 'session': 'admin'},
    {'time': '55 sec ago', 'type': 'admin_session', 'details': 'connected', 'session': 'system'},
    {'time': '1.5 min ago', 'type': 'snapshot_saved', 'details': 'visitor_001.jpg', 'session': 'system'},
    {'time': '2 min ago', 'type': 'command_head', 'details': 'lr:45 ud:55', 'session': 'admin'},
    {'time': '2.5 min ago', 'type': 'command_drive', 'details': 'dir: back', 'session': 'admin'},
    {'time': '3.5 min ago', 'type': 'visitor_checkin', 'details': 'guest #200', 'session': 'system'},
    {'time': '4 min ago', 'type': 'command_head', 'details': 'lr:50 ud:48', 'session': 'admin'},
    {'time': '4.5 min ago', 'type': 'command_drive', 'details': 'dir: right', 'session': 'admin'},
    {'time': '5 min ago', 'type': 'safety_stop', 'details': 'triggered_by: system', 'session': 'system'},
    {'time': '5.5 min ago', 'type': 'admin_session', 'details': 'disconnected', 'session': 'system'},
    {'time': '6 min ago', 'type': 'command_head', 'details': 'lr:60 ud:40', 'session': 'admin'},
    {'time': '6.5 min ago', 'type': 'snapshot_saved', 'details': 'detection_001.jpg', 'session': 'system'},
    {'time': '7 min ago', 'type': 'visitor_checkin', 'details': 'guest #205', 'session': 'system'},
    {'time': '7.5 min ago', 'type': 'command_drive', 'details': 'dir: forward', 'session': 'admin'},
    {'time': '8.5 min ago', 'type': 'command_head', 'details': 'lr:40 ud:60', 'session': 'admin'},
    {'time': '9.5 min ago', 'type': 'admin_session', 'details': 'connected', 'session': 'system'},
    {'time': '10 min ago', 'type': 'command_drive', 'details': 'dir: left', 'session': 'admin'},
    {'time': '10.5 min ago', 'type': 'visitor_checkin', 'details': 'guest #212', 'session': 'system'},
    {'time': '11 min ago', 'type': 'snapshot_saved', 'details': 'reception_001.jpg', 'session': 'system'},
    {'time': '11.5 min ago', 'type': 'command_head', 'details': 'lr:50 ud:50', 'session': 'admin'},
  ];

  @override
  Widget build(BuildContext context) {
    // Prepend REAL recognizer detections as they arrive (no mock face rows).
    ref.listen<FaceDetection?>(faceDetectionProvider, (prev, next) {
      if (next == null) return;
      setState(() {
        _events.insert(0, {
          'time': 'just now',
          'type': 'face_detected',
          'details': next.matched
              ? '${next.name} · L2 ${next.distance.toStringAsFixed(2)}'
              : 'unknown · L2 ${next.distance.toStringAsFixed(2)}',
          'session': 'system',
        });
      });
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.receipt_long, size: 28, color: MikeeColors.primary), const SizedBox(width: 12), Text('Event Log', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold))]),
                const SizedBox(height: 4),
                Text('Full system + command audit trail', style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
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
              Text('${_events.length} of ${_events.length} events', style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted)),
            ]),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]), border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(children: [
                    SizedBox(width: 130, child: Text('TIME', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textMuted))),
                    SizedBox(width: 210, child: Text('EVENT', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textMuted))),
                    Expanded(child: Text('DETAILS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textMuted))),
                    SizedBox(width: 150, child: Text('SESSION', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textMuted))),
                  ]),
                ),
                Container(height: 1, color: MikeeColors.border),
                ..._events.asMap().entries.map((e) => _EventRow(e.key, e.value)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip(this.label, this.active, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), decoration: BoxDecoration(color: active ? MikeeColors.primary : Colors.transparent, border: Border.all(color: active ? MikeeColors.primary : MikeeColors.border), borderRadius: BorderRadius.circular(20)), child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: active ? Colors.white : MikeeColors.textSecondary)))));
  }
}

class _EventRow extends StatelessWidget {
  final int idx;
  final Map<String, String> event;
  const _EventRow(this.idx, this.event);
  @override
  Widget build(BuildContext context) {
    final color = eventColorMap[event['type']] ?? MikeeColors.textMuted;
    return Container(
      color: idx % 2 == 1 ? Colors.white.withOpacity(0.012) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(children: [
        SizedBox(width: 130, child: Text(event['time']!, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: MikeeColors.textSecondary))),
        SizedBox(width: 210, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.12), border: Border.all(color: color.withOpacity(0.25)), borderRadius: BorderRadius.circular(6)), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)), const SizedBox(width: 6), Text(event['type']!, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500, color: color))]))),
        Expanded(child: Text(event['details']!, style: GoogleFonts.jetBrainsMono(fontSize: 13, color: Colors.white.withOpacity(0.85)))),
        SizedBox(width: 150, child: Row(children: [Icon(event['session'] == 'admin' ? Icons.person : Icons.memory, size: 14, color: MikeeColors.textSecondary), const SizedBox(width: 6), Text(event['session']!, style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textSecondary))])),
      ]),
    );
  }
}
