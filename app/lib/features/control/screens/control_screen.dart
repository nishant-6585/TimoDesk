import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/spine/spine_provider.dart';
import '../../../services/spine/spine_state.dart';
import '../../live_feed/widgets/mjpeg_view.dart';
import '../../settings/providers/settings_provider.dart';
import '../widgets/joystick.dart';
import '../widgets/sensor_status_card.dart';
import '../widgets/blocked_overlay.dart';

class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  double _driveX = 0, _driveY = 0;
  double _headX = 50, _headY = 50;
  double _maxSpeed = 0.5;
  String _driveStatus = 'IDLE';
  int _throttle = 0;
  bool _wasDriving = false; // true while a drive command is active (joystick out of deadzone)
  Timer? _headThrottleTimer;

  @override
  void dispose() {
    _headThrottleTimer?.cancel();
    super.dispose();
  }

  void _handleDriveJoystick(double x, double y, double mag) {
    // Update UI state
    setState(() {
      _driveX = x;
      _driveY = y;
      const deadzone = 0.15;
      if (mag < deadzone) {
        _driveStatus = 'IDLE';
        _throttle = 0;
      } else {
        _throttle = ((mag - deadzone) / (1 - deadzone) * 100).toInt().clamp(0, 100);
        if (y.abs() > x.abs()) {
          _driveStatus = y > 0 ? 'FORWARD' : 'REVERSE';
        } else {
          _driveStatus = x > 0 ? 'RIGHT' : 'LEFT';
        }
      }
    });

    // Validate online status immediately before sending intent
    final spineState = ref.read(spineProvider);
    final isOnline = spineState.status?.online ?? false;

    // Joystick returned to the deadzone (released or centered) → halt the wheels.
    // The robot_app holds a moveSerial heartbeat until it receives stop, so we
    // MUST send stop_drive on release or the robot keeps moving. Only send it on
    // the moving→idle transition (not on every idle frame), and only if we were
    // actually driving. stop_drive does not latch the global STOP interlock.
    if (_driveStatus == 'IDLE') {
      if (_wasDriving) {
        _wasDriving = false;
        if (isOnline) {
          ref.read(spineProvider.notifier).sendIntent({'intent': 'stop_drive'});
        }
      }
      return;
    }

    // Send drive command ONLY if joystick is not in deadzone and robot is online
    if (!isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Robot offline - command not sent', style: GoogleFonts.inter(fontSize: 12))),
        );
      }
      return;
    }
    final dir = _driveStatus == 'FORWARD' ? 'forward' :
                _driveStatus == 'REVERSE' ? 'back' :
                _driveStatus == 'RIGHT' ? 'right' : 'left';

    // Re-validate online status immediately before sending
    if (ref.read(spineProvider).status?.online ?? false) {
      _wasDriving = true;
      final notifier = ref.read(spineProvider.notifier);
      notifier.sendIntent({'intent': 'drive', 'dir': dir});
    }
  }

  void _handleHeadJoystick(double x, double y, double mag) {
    setState(() {
      _headX = ((x + 1) / 2 * 100).clamp(0, 100);
      _headY = ((y + 1) / 2 * 100).clamp(0, 100);
    });

    final spineState = ref.read(spineProvider);
    final isOnline = spineState.status?.online ?? false;

    if (!isOnline) {
      return;
    }

    // Throttle head commands to prevent flooding WebSocket
    _headThrottleTimer?.cancel();
    _headThrottleTimer = Timer(joystickThrottleMs, () {
      if (mounted) {
        // Re-validate online status within debounce callback
        if (ref.read(spineProvider).status?.online ?? false) {
          final notifier = ref.read(spineProvider.notifier);
          notifier.sendIntent({'intent': 'head', 'lr': _headX.toInt(), 'ud': _headY.toInt()});
        }
      }
    });
  }

  void _resetHead() {
    final spineState = ref.read(spineProvider);
    final isOnline = spineState.status?.online ?? false;

    setState(() {
      _headX = 50;
      _headY = 50;
    });

    if (!isOnline) {
      return;
    }

    // Re-validate online status immediately before sending
    if (ref.read(spineProvider).status?.online ?? false) {
      final notifier = ref.read(spineProvider.notifier);
      notifier.sendIntent({'intent': 'head', 'lr': 50, 'ud': 50});
    }
  }

  void _sendGesture(String gesture) {
    final spineState = ref.read(spineProvider);
    final isOnline = spineState.status?.online ?? false;

    if (spineState.stopped) {
      return;
    }

    if (!isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Robot offline - command not sent', style: GoogleFonts.inter(fontSize: 12))),
        );
      }
      return;
    }

    // Re-validate online status immediately before sending
    if (ref.read(spineProvider).status?.online ?? false) {
      final notifier = ref.read(spineProvider.notifier);
      notifier.sendIntent({'intent': gesture});
    }
  }

  void _handleStopResume() {
    final spineState = ref.read(spineProvider);
    final isOnline = spineState.status?.online ?? false;

    if (!isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Robot offline - command not sent', style: GoogleFonts.inter(fontSize: 12))),
        );
      }
      return;
    }

    // Re-validate online status immediately before sending
    if (ref.read(spineProvider).status?.online ?? false) {
      final notifier = ref.read(spineProvider.notifier);
      if (spineState.stopped) {
        notifier.sendIntent({'intent': 'resume'});
      } else {
        notifier.sendIntent({'intent': 'stop'});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spine = ref.watch(spineProvider);
    final stopped = spine.stopped;
    final isBlocked = spine.status?.obstacleState == ObstacleState.blocked;

    // Body-only: the AppShell supplies the top status bar + sidebar.
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: _ControlContent(
                driveStatus: _driveStatus,
                throttle: _throttle,
                pan: _headX.toInt(),
                tilt: _headY.toInt(),
                maxSpeed: _maxSpeed,
                onMaxSpeedChange: (v) => setState(() => _maxSpeed = v),
                onDriveJoystick: _handleDriveJoystick,
                onHeadJoystick: _handleHeadJoystick,
                onGesture: _sendGesture,
                onCenterHead: _resetHead,
                onStopResume: _handleStopResume,
                stopped: stopped,
                status: spine.status,
              ),
            ),
          ),
        ),
        // Blocked overlay (obstacle detected)
        BlockedOverlay(visible: isBlocked),
      ],
    );
  }
}

class _ControlContent extends StatelessWidget {
  final String driveStatus;
  final int throttle, pan, tilt;
  final double maxSpeed;
  final Function(double) onMaxSpeedChange;
  final Function(double, double, double) onDriveJoystick;
  final Function(double, double, double) onHeadJoystick;
  final Function(String) onGesture;
  final VoidCallback onCenterHead;
  final VoidCallback onStopResume;
  final bool stopped;
  final RobotStatus? status;

  const _ControlContent({
    required this.driveStatus,
    required this.throttle,
    required this.pan,
    required this.tilt,
    required this.maxSpeed,
    required this.onMaxSpeedChange,
    required this.onDriveJoystick,
    required this.onHeadJoystick,
    required this.onGesture,
    required this.onCenterHead,
    required this.onStopResume,
    required this.stopped,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [Icon(Icons.sports_esports, size: 28, color: MikeeColors.primary), const SizedBox(width: 16), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Control Room', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Direct teleoperation — drive and look with the joysticks', style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
        ])]),
        TextButton.icon(onPressed: () {}, icon: const Icon(Icons.fullscreen, size: 20), label: Text('Pop out feed', style: GoogleFonts.inter(fontSize: 13))),
      ]),
      const SizedBox(height: 24),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: _LiveFeedCard()),
        const SizedBox(width: 20),
        Expanded(flex: 2, child: Column(children: [
          _TelemetryCard(driveStatus: driveStatus, throttle: throttle, pan: pan, tilt: tilt, maxSpeed: maxSpeed, onMaxSpeedChange: onMaxSpeedChange),
          if (status != null) ...[
            const SizedBox(height: 20),
            SensorStatusCard(status: status!),
          ]
        ])),
      ]),
      const SizedBox(height: 20),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _DriveCard(status: driveStatus, onJoystick: onDriveJoystick, disabled: stopped)),
        const SizedBox(width: 20),
        Expanded(child: _HeadLookCard(pan: pan, tilt: tilt, onJoystick: onHeadJoystick, disabled: stopped)),
        const SizedBox(width: 20),
        Expanded(child: _GesturesCard(onGesture: onGesture, onCenterHead: onCenterHead)),
      ]),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
        onPressed: onStopResume,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEF4444),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
        ),
        child: Text(
          stopped ? 'RESUME' : 'EMERGENCY STOP',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.05)
        )
      )),
    ]);
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _streaming ? MikeeColors.error : MikeeColors.textMuted)), const SizedBox(width: 8), Text(_streaming ? 'LIVE' : 'OFFLINE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _streaming ? MikeeColors.error : MikeeColors.textMuted, letterSpacing: 0.1))]),
          InkWell(
            onTap: () => setState(() => _streaming = !_streaming),
            borderRadius: BorderRadius.circular(8),
            child: Padding(padding: const EdgeInsets.all(2), child: Icon(_streaming ? Icons.stop_circle_outlined : Icons.play_circle_outline, size: 22, color: _streaming ? MikeeColors.error : MikeeColors.primary)),
          ),
        ]),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: _streaming
              ? ClipRRect(borderRadius: BorderRadius.circular(8), child: MjpegView(url: url))
              : Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.videocam_off, size: 56, color: const Color(0xFF3A3A3A)),
                    const SizedBox(height: 10),
                    TextButton.icon(onPressed: () => setState(() => _streaming = true), icon: const Icon(Icons.play_arrow, size: 18), label: Text('Start stream', style: GoogleFonts.inter(fontSize: 12))),
                  ]),
                ),
        ),
        const SizedBox(height: 12),
        Text('Live Feed · $robotIp:$robotCameraPort', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: MikeeColors.textSecondary)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('RES 640×480', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: MikeeColors.textMuted)), Text(_streaming ? 'MJPEG' : 'IDLE', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: _streaming ? MikeeColors.success : MikeeColors.textMuted)), Text('PORT $robotCameraPort', style: GoogleFonts.jetBrainsMono(fontSize: 10))]),
      ]),
    );
  }
}

class _TelemetryCard extends StatelessWidget {
  final String driveStatus;
  final int throttle, pan, tilt;
  final double maxSpeed;
  final Function(double) onMaxSpeedChange;
  const _TelemetryCard({required this.driveStatus, required this.throttle, required this.pan, required this.tilt, required this.maxSpeed, required this.onMaxSpeedChange});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]), border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TELEMETRY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
        const SizedBox(height: 12),
        GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.8, children: [_StatTile('DRIVE', driveStatus, Icons.directions), _StatTile('THROTTLE', '$throttle%', Icons.trending_up), _StatTile('PAN', pan.toString(), Icons.pan_tool), _StatTile('TILT', tilt.toString(), Icons.zoom_out_map)]),
        const SizedBox(height: 16),
        Divider(color: MikeeColors.border, height: 1),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('MAX SPEED', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: MikeeColors.textSecondary)), Text('${maxSpeed.toStringAsFixed(1)}x', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: MikeeColors.primary))]),
        const SizedBox(height: 8),
        _McSlider(value: maxSpeed * 100, min: 30, max: 80, onChanged: (v) => onMaxSpeedChange(v / 100)),
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _StatTile(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF141414), border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(12)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 16, color: MikeeColors.textSecondary), const SizedBox(height: 6), Text(label, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: MikeeColors.textMuted)), Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.bold))]));
  }
}

class _DriveCard extends StatelessWidget {
  final String status;
  final Function(double, double, double) onJoystick;
  final bool disabled;
  const _DriveCard({required this.status, required this.onJoystick, required this.disabled});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]), border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('DRIVE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)), Text(status, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: MikeeColors.primary))]), const SizedBox(height: 12), Center(child: Joystick(size: 200, knobColor: MikeeColors.primary, onChange: onJoystick, disabled: disabled)), const SizedBox(height: 12), Center(child: Text('FORWARD · REVERSE · TURN', style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted, letterSpacing: 0.05)))]));
  }
}

class _HeadLookCard extends StatelessWidget {
  final int pan, tilt;
  final Function(double, double, double) onJoystick;
  final bool disabled;
  const _HeadLookCard({required this.pan, required this.tilt, required this.onJoystick, required this.disabled});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]), border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('HEAD LOOK', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)), Transform.rotate(angle: (pan - 50) * 0.5 * 3.14159 / 180, child: Icon(Icons.smart_toy, size: 20, color: MikeeColors.primary))]), const SizedBox(height: 12), Center(child: Joystick(size: 200, knobColor: const Color(0xFF3B82F6), onChange: onJoystick, disabled: disabled)), const SizedBox(height: 12), Center(child: Text('PAN · TILT', style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted, letterSpacing: 0.05)))]));
  }
}

class _GesturesCard extends StatelessWidget {
  final Function(String) onGesture;
  final VoidCallback onCenterHead;
  const _GesturesCard({required this.onGesture, required this.onCenterHead});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]), border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('GESTURES', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)), const SizedBox(height: 12), GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.4, children: [_GestureButton('Wave', Icons.waving_hand, () => onGesture('wave')), _GestureButton('Snapshot', Icons.photo_camera, () => onGesture('snapshot')), _GestureButton('Go Home', Icons.home, () => onGesture('home')), _GestureButton('Nod', Icons.smart_toy, () => onGesture('nod'))]), const SizedBox(height: 12), SizedBox(width: double.infinity, height: 40, child: ElevatedButton.icon(onPressed: onCenterHead, icon: const Icon(Icons.center_focus_strong, size: 16), label: Text('Center head', style: GoogleFonts.inter(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: MikeeColors.cardTop, foregroundColor: MikeeColors.textPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), side: const BorderSide(color: MikeeColors.border))))]));
  }
}

class _GestureButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GestureButton(this.label, this.icon, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Material(
      color: MikeeColors.inset,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 20, color: MikeeColors.primary),
            const SizedBox(height: 6),
            Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: MikeeColors.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

class _McSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  const _McSlider({required this.value, required this.min, required this.max, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: MikeeColors.primary,
        inactiveTrackColor: MikeeColors.border,
        thumbColor: MikeeColors.primary,
        overlayColor: MikeeColors.primary.withOpacity(0.15),
        trackHeight: 4,
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }
}
