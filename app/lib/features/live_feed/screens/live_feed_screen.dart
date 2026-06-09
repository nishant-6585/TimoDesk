import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/spine/spine_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../widgets/mjpeg_view.dart';
import '../widgets/face_detection_test.dart';

class LiveFeedScreen extends ConsumerStatefulWidget {
  const LiveFeedScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends ConsumerState<LiveFeedScreen> {
  bool _isRecording = false;
  String _resolution = '640x480';
  String _quality = 'High';

  void _takeSnapshot() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [Icon(Icons.check_circle, color: TimoColors.success, size: 20), const SizedBox(width: 12), Text('Snapshot saved', style: GoogleFonts.inter(fontSize: 13))]),
        backgroundColor: TimoColors.cardTop,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleRecord() {
    setState(() => _isRecording = !_isRecording);
  }

  void _openFaceDetectionTest() {
    final settings = ref.read(settingsProvider);
    final url = 'http://${settings.robotIp}:8080/stream'; // Camera port always 8080

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: FaceDetectionTest(mjpegUrl: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: TimoColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              // Header
              Container(
                height: 64,
                decoration: BoxDecoration(color: TimoColors.surface.withOpacity(0.8), border: const Border(bottom: BorderSide(color: TimoColors.border))),
                padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Row(children: [
                    Container(width: 36, height: 36, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [TimoColors.primary, TimoColors.primaryDark]), boxShadow: [BoxShadow(color: TimoColors.primary.withOpacity(0.35), blurRadius: 16)]), child: Center(child: Text('X', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)))),
                    if (!compact) ...[const SizedBox(width: 12), Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('TimoDesk', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: TimoColors.textPrimary, height: 1.0)), Text('xboom', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.15, color: TimoColors.textMuted, height: 1.0))])]
                  ]),
                  if (!compact) Text('Live Feed', style: GoogleFonts.inter(fontSize: 13, color: TimoColors.textSecondary)),
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: TimoColors.success.withOpacity(0.08), border: Border.all(color: TimoColors.success.withOpacity(0.3)), borderRadius: BorderRadius.circular(8)), child: Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: TimoColors.success)), const SizedBox(width: 8), Text('ONLINE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: TimoColors.success))])),
                    const SizedBox(width: 12),
                    Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: TimoColors.border, width: 2), color: const Color(0xFF2A2A2A)), child: Center(child: Text('NK', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)))),
                  ]),
                ]),
              ),
              // Sidebar + Content
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
                                  Row(children: [Icon(Icons.videocam, size: 28, color: TimoColors.primary), const SizedBox(width: 12), Text('Live Feed', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold))]),
                                  const SizedBox(height: 4),
                                  Text('Camera stream · ${ref.watch(settingsProvider).robotIp}:$robotCameraPort', style: GoogleFonts.inter(fontSize: 13, color: TimoColors.textSecondary)),
                                ]),
                                Row(children: [
                                  TextButton.icon(onPressed: _takeSnapshot, icon: const Icon(Icons.photo_camera, size: 20), label: Text('Snapshot', style: GoogleFonts.inter(fontSize: 13))),
                                  const SizedBox(width: 12),
                                  TextButton.icon(
                                    onPressed: _openFaceDetectionTest,
                                    icon: const Icon(Icons.face, size: 20),
                                    label: Text('Face Test', style: GoogleFonts.inter(fontSize: 13)),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: _toggleRecord,
                                    style: ElevatedButton.styleFrom(backgroundColor: _isRecording ? const Color(0xFFEF4444) : TimoColors.cardTop, foregroundColor: Colors.white, side: BorderSide(color: _isRecording ? const Color(0xFFEF4444) : TimoColors.border)),
                                    child: Text(_isRecording ? 'Stop Rec' : 'Record', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                                  ),
                                ]),
                              ]),
                              const SizedBox(height: 20),
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(flex: 3, child: _LiveFeedCard()),
                                const SizedBox(width: 20),
                                Expanded(flex: 1, child: Column(children: [
                                  _CameraCard(resolution: _resolution, quality: _quality, onResolutionChange: (v) => setState(() => _resolution = v), onQualityChange: (v) => setState(() => _quality = v)),
                                  const SizedBox(height: 20),
                                  _StreamStatsCard(),
                                ])),
                              ]),
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
      child: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [
          _NavItem('Dashboard', Icons.space_dashboard, false, () => onNav('dashboard')),
          _NavItem('Control', Icons.sports_esports, false, () => onNav('control')),
          _NavItem('Live Feed', Icons.videocam, true, () => onNav('feed')),
          _NavItem('Gallery', Icons.photo_library, false, () => onNav('gallery')),
          _NavItem('Event Log', Icons.receipt_long, false, () => onNav('events')),
          _NavItem('Settings', Icons.settings, false, () => onNav('settings')),
        ])),
      ]),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: active ? TimoColors.primary.withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          if (active) Container(width: 4, height: 20, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: TimoColors.primary, borderRadius: BorderRadius.circular(999))),
          Icon(icon, size: 20, color: active ? TimoColors.primary : TimoColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: active ? FontWeight.w500 : FontWeight.normal, color: active ? TimoColors.primary : TimoColors.textSecondary))),
        ]),
      ))),
    );
  }
}

class _LiveFeedCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_LiveFeedCard> createState() => _LiveFeedCardState();
}

class _LiveFeedCardState extends ConsumerState<_LiveFeedCard> {
  bool _streaming = false;

  @override
  Widget build(BuildContext context) {
    final robotIp = ref.watch(settingsProvider).robotIp;
    final url = robotStreamUrl(robotIp);

    return Container(
      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _streaming ? TimoColors.error : TimoColors.textMuted)), const SizedBox(width: 8), Text(_streaming ? 'LIVE' : 'OFFLINE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _streaming ? TimoColors.error : TimoColors.textMuted, letterSpacing: 0.1))]),
            InkWell(
              onTap: () => setState(() => _streaming = !_streaming),
              borderRadius: BorderRadius.circular(8),
              child: Padding(padding: const EdgeInsets.all(4), child: Icon(_streaming ? Icons.stop_circle_outlined : Icons.play_circle_outline, size: 22, color: _streaming ? TimoColors.error : TimoColors.primary)),
            ),
          ]),
        ),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: _streaming
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: MjpegView(url: url),
                )
              : _StreamPlaceholder(onStart: () => setState(() => _streaming = true)),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [Text('Live Feed · $robotIp:$robotCameraPort', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: TimoColors.textSecondary)), const SizedBox(height: 12), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('RES 640×480', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: TimoColors.textMuted)), Text(_streaming ? 'MJPEG' : 'IDLE', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: _streaming ? TimoColors.success : TimoColors.textMuted)), Text('PORT $robotCameraPort', style: GoogleFonts.jetBrainsMono(fontSize: 10))])]),
        ),
      ]),
    );
  }
}

class _StreamPlaceholder extends StatelessWidget {
  final VoidCallback onStart;
  const _StreamPlaceholder({required this.onStart});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.videocam_off, size: 56, color: const Color(0xFF3A3A3A)),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: Text('Start stream', style: GoogleFonts.inter(fontSize: 13)),
        ),
      ]),
    );
  }
}

class _CameraCard extends StatelessWidget {
  final String resolution, quality;
  final Function(String) onResolutionChange, onQualityChange;
  const _CameraCard({required this.resolution, required this.quality, required this.onResolutionChange, required this.onQualityChange});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [TimoColors.cardTop, TimoColors.cardBottom]), border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('CAMERA', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textSecondary)),
        const SizedBox(height: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Resolution', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: TimoColors.textSecondary)), const SizedBox(height: 8), Row(children: [
          Expanded(child: _SegmentButton('320×240', resolution == '320x240', () => onResolutionChange('320x240'))),
          const SizedBox(width: 8),
          Expanded(child: _SegmentButton('640×480', resolution == '640x480', () => onResolutionChange('640x480'))),
        ])]),
        const SizedBox(height: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Quality', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: TimoColors.textSecondary)), const SizedBox(height: 8), Row(children: [
          Expanded(child: _SegmentButton('Low', quality == 'Low', () => onQualityChange('Low'))),
          const SizedBox(width: 8),
          Expanded(child: _SegmentButton('High', quality == 'High', () => onQualityChange('High'))),
        ])]),
      ]),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SegmentButton(this.label, this.active, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? TimoColors.primary : TimoColors.inset,
        border: Border.all(color: active ? TimoColors.primary : TimoColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: active ? Colors.white : TimoColors.textSecondary))),
    )));
  }
}

class _StreamStatsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [TimoColors.cardTop, TimoColors.cardBottom]), border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('STREAM STATS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textSecondary)),
        const SizedBox(height: 12),
        _StatRow('Resolution', '640×480'),
        _StatRow('FPS', '15'),
        _StatRow('Latency', '45ms'),
        _StatRow('Bitrate', '1.2 Mbps'),
        _StatRow('Codec', 'MJPEG'),
      ]),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label, value;
  const _StatRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: TimoColors.textSecondary)),
        Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
