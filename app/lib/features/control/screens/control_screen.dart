import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

    // Send drive command ONLY if joystick is not in deadzone and robot is online
    if (_driveStatus != 'IDLE') {
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
        final notifier = ref.read(spineProvider.notifier);
        notifier.sendIntent({'intent': 'drive', 'dir': dir});
      }
    }
    // Do NOT send any command when idle - let robot coast
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
    _headThrottleTimer = Timer(const Duration(milliseconds: joystickThrottleMs), () {
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
    final isOnline = spine.status?.online ?? false;
    final isBlocked = spine.status?.obstacleState == ObstacleState.blocked;
    final compact = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: MikeeColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              // Header
              Container(
                height: 64,
                decoration: BoxDecoration(
                  color: MikeeColors.surface.withOpacity(0.8),
                  border: const Border(bottom: BorderSide(color: MikeeColors.border)),
                ),
                padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [MikeeColors.primary, MikeeColors.primaryDark]),
                          boxShadow: [BoxShadow(color: MikeeColors.primary.withOpacity(0.35), blurRadius: 16)],
                        ),
                        child: Center(child: Text('X', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 12),
                        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Mikee', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary, height: 1.0)),
                          Text('xboom', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.15, color: MikeeColors.textMuted, height: 1.0)),
                        ]),
                      ]
                    ]),
                    if (!compact) Text('Control Room', style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: (isOnline ? MikeeColors.success : MikeeColors.error).withOpacity(0.08),
                          border: Border.all(color: (isOnline ? MikeeColors.success : MikeeColors.error).withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: isOnline ? MikeeColors.success : MikeeColors.error)),
                          const SizedBox(width: 8),
                          Text(isOnline ? 'ONLINE' : 'OFFLINE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: isOnline ? MikeeColors.success : MikeeColors.error)),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: MikeeColors.border, width: 2), color: const Color(0xFF2A2A2A)), child: Center(child: Text('NK', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)))),
                    ]),
                  ],
                ),
              ),
              // Sidebar + Content
              Expanded(
                child: Row(
                  children: [
                    if (!compact) _Sidebar(onNav: (route) {
                      final routes = {'dashboard': '/', 'control': '/control', 'feed': '/live-feed', 'gallery': '/gallery', 'events': '/event-log', 'patrol_routes': '/patrol-routes', 'settings': '/settings'};
                      if (routes.containsKey(route)) context.go(routes[route]!);
                    }),
                    Expanded(
                      child: SingleChildScrollView(
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
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Blocked overlay (obstacle detected)
          BlockedOverlay(visible: isBlocked),
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
      decoration: BoxDecoration(color: MikeeColors.surface, border: const Border(right: BorderSide(color: MikeeColors.border))),
      child: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [
          _NavItem('Dashboard', Icons.space_dashboard, false, () => onNav('dashboard')),
          _NavItem('Control', Icons.sports_esports, true, () => onNav('control')),
          _NavItem('Live Feed', Icons.videocam, false, () => onNav('feed')),
          _NavItem('Gallery', Icons.photo_library, false, () => onNav('gallery')),
          _NavItem('Event Log', Icons.receipt_long, false, () => onNav('events')),
          _NavItem('Patrol Routes', Icons.route, false, () => onNav('patrol_routes')),
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
        decoration: BoxDecoration(color: active ? MikeeColors.primary.withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          if (active) Container(width: 4, height: 20, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: MikeeColors.primary, borderRadius: BorderRadius.circular(999))),
          Icon(icon, size: 20, color: active ? MikeeColors.primary : MikeeColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: active ? FontWeight.w500 : FontWeight.normal, color: active ? MikeeColors.primary : MikeeColors.textSecondary))),
        ]),
      ))),
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
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]), border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('GESTURES', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)), const SizedBox(height: 12), GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.4, children: [_GestureButton('Wave', Icons.waving_hand, () => onGesture('wave')), _GestureButton('Snapshot', Icons.photo_camera, () => onGesture('snapshot')), _GestureButton('Go Home', Icons.home, () => onGesture('home')), _GestureButton('Nod', Icons.smart_toy, () => onGesture('nod'))]), const SizedBox(height: 12), SizedBox(width: double.infinity, height: 40, child: ElevatedButton.icon(onPressed: onCenterHead, icon: const Icon(Icons.center_focus_strong, size: 16), label: Text('Center head', style: GoogleFonts.inter(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: MikeeColors.cardTop, foregroundColor: MikeeColors.textPrim
