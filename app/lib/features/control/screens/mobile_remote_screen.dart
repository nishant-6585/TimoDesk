import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/spine/spine_provider.dart';
import '../../../services/spine/spine_state.dart';
import '../../live_feed/widgets/mjpeg_view.dart';
import '../../settings/providers/settings_provider.dart';
import '../widgets/joystick.dart';

/// Phone-first remote: full-bleed camera + drive/head joysticks + arm/wave +
/// an always-visible STOP/RESUME. Shares spine_service/providers/MjpegView with
/// the desktop ControlScreen — this is just the small-screen layout (#90 Part A).
class MobileRemoteScreen extends ConsumerStatefulWidget {
  const MobileRemoteScreen({super.key});

  @override
  ConsumerState<MobileRemoteScreen> createState() => _MobileRemoteScreenState();
}

class _MobileRemoteScreenState extends ConsumerState<MobileRemoteScreen> {
  bool _streaming = false;
  String _driveStatus = 'IDLE';
  late DateTime _lastDrive;
  late DateTime _lastHead;

  @override
  void initState() {
    super.initState();
    // Initialize throttle timestamps to now to prevent unthrottled burst on first joystick movement.
    _lastDrive = DateTime.now();
    _lastHead = DateTime.now();
  }

  // ── Intents (mirror ControlScreen; throttled drive) ────────────────────────
  void _handleDrive(double x, double y, double mag) {
    const deadzone = 0.15;
    String status;
    if (mag < deadzone) {
      status = 'IDLE';
    } else if (y.abs() > x.abs()) {
      status = y > 0 ? 'FORWARD' : 'REVERSE';
    } else {
      status = x > 0 ? 'RIGHT' : 'LEFT';
    }
    if (status != _driveStatus) {
      if (status != 'IDLE') HapticFeedback.selectionClick();
      setState(() => _driveStatus = status);
    }
    if (status == 'IDLE') return; // coast — send nothing

    // Throttle drive intents to joystickThrottleMs.
    final now = DateTime.now();
    if (now.difference(_lastDrive) < joystickThrottleMs) return;
    _lastDrive = now;

    // Verify robot is online before sending intent.
    if (!(ref.read(spineProvider).status?.online ?? false)) return;

    final dir = status == 'FORWARD'
        ? 'forward'
        : status == 'REVERSE'
            ? 'back'
            : status == 'RIGHT'
                ? 'right'
                : 'left';
    ref.read(spineProvider.notifier).sendIntent({'intent': 'drive', 'dir': dir});
  }

  void _handleHead(double x, double y, double mag) {
    // Throttle head intents to joystickThrottleMs (same as drive).
    final now = DateTime.now();
    if (now.difference(_lastHead) < joystickThrottleMs) return;
    _lastHead = now;

    // Verify robot is online before sending intent.
    if (!(ref.read(spineProvider).status?.online ?? false)) return;

    final lr = ((x + 1) / 2 * 100).clamp(0, 100).toInt();
    final ud = ((y + 1) / 2 * 100).clamp(0, 100).toInt();
    ref.read(spineProvider.notifier).sendIntent({'intent': 'head', 'lr': lr, 'ud': ud});
  }

  void _gesture(String intent) {
    if (ref.read(spineProvider).stopped) return;
    ref.read(spineProvider.notifier).sendIntent({'intent': intent});
  }

  void _stopResume() {
    HapticFeedback.heavyImpact();
    final stopped = ref.read(spineProvider).stopped;
    ref.read(spineProvider.notifier).sendIntent({'intent': stopped ? 'resume' : 'stop'});
  }

  @override
  Widget build(BuildContext context) {
    final spine = ref.watch(spineProvider);
    final stopped = spine.stopped;
    final robotIp = ref.watch(settingsProvider).robotIp;
    final landscape = MediaQuery.of(context).orientation == Orientation.landscape;

    final camera = _CameraPanel(
      streaming: _streaming,
      url: robotStreamUrl(robotIp),
      onToggle: () => setState(() => _streaming = !_streaming),
    );
    final controls = _ControlsPanel(
      driveStatus: _driveStatus,
      stopped: stopped,
      onDrive: _handleDrive,
      onHead: _handleHead,
      onGesture: _gesture,
    );

    return Scaffold(
      backgroundColor: MikeeColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _StatusStrip(spine: spine, onSettings: () => context.go('/settings')),
            Expanded(
              child: landscape
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(flex: 5, child: camera),
                      Expanded(flex: 4, child: SingleChildScrollView(child: controls)),
                    ])
                  : SingleChildScrollView(
                      child: Column(children: [
                        SizedBox(height: 220, child: camera),
                        controls,
                      ]),
                    ),
            ),
            _StopResumeBar(stopped: stopped, onTap: _stopResume),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

// ── Status strip: connection · battery · SDK · obstacle ───────────────────────
class _StatusStrip extends StatelessWidget {
  final SpineState spine;
  final VoidCallback onSettings;
  const _StatusStrip({required this.spine, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    final s = spine.status;
    final online = s?.online ?? false;
    final blocked = s?.obstacleState == ObstacleState.blocked;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: MikeeColors.surface,
        border: Border(bottom: BorderSide(color: MikeeColors.border)),
      ),
      child: Row(children: [
        _Pill(
          color: spine.connected ? MikeeColors.success : MikeeColors.error,
          label: spine.connected ? 'LINKED' : 'NO LINK',
        ),
        const SizedBox(width: 8),
        _Pill(color: online ? MikeeColors.success : MikeeColors.textMuted, label: online ? 'SDK' : 'SDK?'),
        const SizedBox(width: 8),
        Icon(Icons.battery_full, size: 16, color: _batteryColor(s?.battery ?? 0)),
        Text(' ${s?.battery ?? '--'}%',
            style: GoogleFonts.jetBrainsMono(fontSize: 12, color: MikeeColors.textSecondary)),
        const Spacer(),
        if (blocked) const _Pill(color: MikeeColors.error, label: 'BLOCKED'),
        // TODO(#90): richer sensor state — SensorStatusCard (lidar/rgbd/sonar) is
        // available on main; the compact strip shows obstacle/battery for now.
        IconButton(
          icon: const Icon(Icons.settings, size: 18, color: MikeeColors.textSecondary),
          onPressed: onSettings,
          tooltip: 'Settings',
        ),
      ]),
    );
  }

  Color _batteryColor(int b) =>
      b <= 15 ? MikeeColors.error : (b <= 35 ? MikeeColors.warning : MikeeColors.success);
}

class _Pill extends StatelessWidget {
  final Color color;
  final String label;
  const _Pill({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 5),
        Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}

// ── Camera panel (full-bleed MjpegView + start/stop) ──────────────────────────
class _CameraPanel extends StatelessWidget {
  final bool streaming;
  final String url;
  final VoidCallback onToggle;
  const _CameraPanel({required this.streaming, required this.url, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        if (streaming)
          MjpegView(url: url)
        else
          Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.videocam_off, size: 48, color: Color(0xFF3A3A3A)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onToggle,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text('Start stream', style: GoogleFonts.inter(fontSize: 13)),
              ),
            ]),
          ),
        Positioned(
          top: 8,
          right: 8,
          child: InkWell(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: Icon(streaming ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                  size: 22, color: streaming ? MikeeColors.error : MikeeColors.primary),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Controls: drive joystick · head pad · arm/wave ────────────────────────────
class _ControlsPanel extends StatelessWidget {
  final String driveStatus;
  final bool stopped;
  final void Function(double, double, double) onDrive;
  final void Function(double, double, double) onHead;
  final void Function(String) onGesture;
  const _ControlsPanel({
    required this.driveStatus,
    required this.stopped,
    required this.onDrive,
    required this.onHead,
    required this.onGesture,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Labeled('DRIVE · $driveStatus', Joystick(size: 150, knobColor: MikeeColors.primary, onChange: onDrive, disabled: stopped)),
          _Labeled('HEAD', Joystick(size: 150, knobColor: const Color(0xFF3B82F6), onChange: onHead, disabled: stopped)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _ActionButton('Wave', Icons.waving_hand, stopped ? null : () => onGesture('wave'))),
          const SizedBox(width: 10),
          Expanded(child: _ActionButton('Reset', Icons.refresh, stopped ? null : () => onGesture('reset_body'))),
          const SizedBox(width: 10),
          Expanded(child: _ActionButton('Snapshot', Icons.photo_camera, stopped ? null : () => onGesture('snapshot'))),
        ]),
      ]),
    );
  }
}

class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labeled(this.label, this.child);
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      child,
      const SizedBox(height: 6),
      Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: MikeeColors.textMuted, letterSpacing: 0.1)),
    ]);
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _ActionButton(this.label, this.icon, this.onTap);
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: MikeeColors.cardTop,
        foregroundColor: MikeeColors.textPrimary,
        side: const BorderSide(color: MikeeColors.border),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 20, color: onTap == null ? MikeeColors.textMuted : MikeeColors.primary),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 11)),
      ]),
    );
  }
}

// ── Always-visible STOP / RESUME ──────────────────────────────────────────────
class _StopResumeBar extends StatelessWidget {
  final bool stopped;
  final VoidCallback onTap;
  const _StopResumeBar({required this.stopped, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: stopped ? MikeeColors.success : MikeeColors.error,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(stopped ? 'RESUME' : 'EMERGENCY STOP',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
        ),
      ),
    );
  }
}
