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

  void _handleDriveJoystick(double x, double y, double mag) {
    setState(() {
      _driveX = x;
      _driveY = y;
      const deadzone = 0.28;
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

    final spineState = ref.read(spineProvider);
    final notifier = ref.read(spineProvider.notifier);

    print('[ControlScreen] Drive joystick: x=$x, y=$y, mag=$mag, status=$_driveStatus, stopped=${spineState.stopped}, connected=${spineState.connected}');

    if (spineState.stopped) {
      print('[ControlScreen] Robot is stopped, not sending drive intent');
      return;
    }

    // Only send movement intents when joystick is NOT idle
    if (_driveStatus != 'IDLE') {
      final dir = _driveStatus == 'FORWARD' ? 'forward' : _driveStatus == 'REVERSE' ? 'back' : _driveStatus == 'RIGHT' ? 'right' : 'left';
      print('[ControlScreen] Sending drive intent: dir=$dir');
      notifier.sendIntent({'intent': 'drive', 'dir': dir});
    } else {
      // When joystick returns to idle, send stop command
      print('[ControlScreen] Joystick idle, sending stop command');
      notifier.sendIntent({'intent': 'stop'});
    }
  }

  void _handleHeadJoystick(double x, double y, double mag) {
    setState(() {
      _headX = ((x + 1) / 2 * 100).clamp(0, 100);
      _headY = ((y + 1) / 2 * 100).clamp(0, 100);
    });

    final spineState = ref.read(spineProvider);
    final notifier = ref.read(spineProvider.notifier);

    print('[ControlScreen] Head joystick: x=$x, y=$y, lr=$_headX, ud=$_headY, stopped=${spineState.stopped}, connected=${spineState.connected}');

    if (spineState.stopped) {
      print('[ControlScreen] Robot is stopped, not sending head intent');
      return;
    }

    print('[ControlScreen] Sending head intent: lr=${_headX.toInt()}, ud=${_headY.toInt()}');
    notifier.sendIntent({'intent': 'head', 'lr': _headX.toInt(), 'ud': _headY.toInt()});
  }

  void _resetHead() {
    setState(() {
      _headX = 50;
      _headY = 50;
    });
    final notifier = ref.read(spineProvider.notifier);
    notifier.sendIntent({'intent': 'head', 'lr': 50, 'ud': 50});
  }

  void _sendGesture(String gesture) {
    final notifier = ref.read(spineProvider.notifier);
    if (ref.read(spineProvider).stopped) return;
    notifier.sendIntent({'intent': gesture});
  }

  @override
  Widget build(BuildContext context) {
    final spine = ref.watch(spineProvider);
    final stopped = spine.stopped;
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
                decoration: BoxDecoration(
                  color: TimoColors.surface.withOpacity(0.8),
                  border: const Border(bottom: BorderSide(color: TimoColors.border)),
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
                          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [TimoColors.primary, TimoColors.primaryDark]),
                          boxShadow: [BoxShadow(color: TimoColors.primary.withOpacity(0.35), blurRadius: 16)],
                        ),
                        child: Center(child: Text('X', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 12),
                        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('TimoDesk', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: TimoColors.textPrimary, height: 1.0)),
                          Text('xboom', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.15, color: TimoColors.textMuted, height: 1.0)),
                        ]),
                      ]
                    ]),
                    if (!compact) Text('Control Room', style: GoogleFonts.inter(fontSize: 13, color: TimoColors.textSecondary)),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: (spine.status?.online ?? false ? TimoColors.success : TimoColors.error).withOpacity(0.08),
                          border: Border.all(color: (spine.status?.online ?? false ? TimoColors.success : TimoColors.error).withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: spine.status?.online ?? false ? TimoColors.success : TimoColors.error)),
                          const SizedBox(width: 8),
                          Text(spine.status?.online ?? false ? 'ONLINE' : 'OFFLINE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: spine.status?.online ?? false ? TimoColors.success : TimoColors.error)),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: TimoColors.border, width: 2), color: const Color(0xFF2A2A2A)), child: Center(child: Text('NK', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)))),
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
          BlockedOverlay(visible: spine.status?.obstacleState == ObstacleState.blocked),
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

class _ControlContent extends StatelessWidget {
  final String driveStatus;
  final int throttle, pan, tilt;
  final double maxSpeed;
  final Function(double) onMaxSpeedChange;
  final Function(double, double, double) onDriveJoystick;
  final Function(double, double, double) onHeadJoystick;
  final Function(String) onGesture;
  final VoidCallback onCenterHead;
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
    required this.stopped,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [Icon(Icons.sports_esports, size: 28, color: TimoColors.primary), const SizedBox(width: 16), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Control Room', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Direct teleoperation — drive and look with the joysticks', style: GoogleFonts.inter(fontSize: 13, color: TimoColors.textSecondary)),
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
      SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: stopped ? () {} : () {}, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(stopped ? 'RESUME' : 'EMERGENCY STOP', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.05)))),
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
      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _streaming ? TimoColors.error : TimoColors.textMuted)), const SizedBox(width: 8), Text(_streaming ? 'LIVE' : 'OFFLINE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _streaming ? TimoColors.error : TimoColors.textMuted, letterSpacing: 0.1))]),
          InkWell(
            onTap: () => setState(() => _streaming = !_streaming),
            borderRadius: BorderRadius.circular(8),
            child: Padding(padding: const EdgeInsets.all(2), child: Icon(_streaming ? Icons.stop_circle_outlined : Icons.play_circle_outline, size: 22, color: _streaming ? TimoColors.error : TimoColors.primary)),
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
        Text('Live Feed · $robotIp:$robotCameraPort', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: TimoColors.textSecondary)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('RES 640×480', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: TimoColors.textMuted)), Text(_streaming ? 'MJPEG' : 'IDLE', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: _streaming ? TimoColors.success : TimoColors.textMuted)), Text('PORT $robotCameraPort', style: GoogleFonts.jetBrainsMono(fontSize: 10))]),
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
      decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [TimoColors.cardTop, TimoColors.cardBottom]), border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TELEMETRY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textSecondary)),
        const SizedBox(height: 12),
        GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.8, children: [_StatTile('DRIVE', driveStatus, Icons.directions), _StatTile('THROTTLE', '$throttle%', Icons.trending_up), _StatTile('PAN', pan.toString(), Icons.pan_tool), _StatTile('TILT', tilt.toString(), Icons.zoom_out_map)]),
        const SizedBox(height: 16),
        Divider(color: TimoColors.border, height: 1),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('MAX SPEED', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: TimoColors.textSecondary)), Text('${maxSpeed.toStringAsFixed(1)}x', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: TimoColors.primary))]),
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
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF141414), border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(12)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 16, color: TimoColors.textSecondary), const SizedBox(height: 6), Text(label, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: TimoColors.textMuted)), Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.bold))]));
  }
}

class _DriveCard extends StatelessWidget {
  final String status;
  final Function(double, double, double) onJoystick;
  final bool disabled;
  const _DriveCard({required this.status, required this.onJoystick, required this.disabled});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [TimoColors.cardTop, TimoColors.cardBottom]), border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('DRIVE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textSecondary)), Text(status, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: TimoColors.primary))]), const SizedBox(height: 12), Center(child: Joystick(size: 200, knobColor: TimoColors.primary, onChange: onJoystick, disabled: disabled)), const SizedBox(height: 12), Center(child: Text('FORWARD · REVERSE · TURN', style: GoogleFonts.inter(fontSize: 11, color: TimoColors.textMuted, letterSpacing: 0.05)))]));
  }
}

class _HeadLookCard extends StatelessWidget {
  final int pan, tilt;
  final Function(double, double, double) onJoystick;
  final bool disabled;
  const _HeadLookCard({required this.pan, required this.tilt, required this.onJoystick, required this.disabled});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [TimoColors.cardTop, TimoColors.cardBottom]), border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('HEAD LOOK', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textSecondary)), Transform.rotate(angle: (pan - 50) * 0.5 * 3.14159 / 180, child: Icon(Icons.smart_toy, size: 20, color: TimoColors.primary))]), const SizedBox(height: 12), Center(child: Joystick(size: 200, knobColor: const Color(0xFF3B82F6), onChange: onJoystick, disabled: disabled)), const SizedBox(height: 12), Center(child: Text('PAN · TILT', style: GoogleFonts.inter(fontSize: 11, color: TimoColors.textMuted, letterSpacing: 0.05)))]));
  }
}

class _GesturesCard extends StatelessWidget {
  final Function(String) onGesture;
  final VoidCallback onCenterHead;
  const _GesturesCard({required this.onGesture, required this.onCenterHead});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [TimoColors.cardTop, TimoColors.cardBottom]), border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('GESTURES', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textSecondary)), const SizedBox(height: 12), GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.4, children: [_GestureButton('Wave', Icons.waving_hand, () => onGesture('wave')), _GestureButton('Snapshot', Icons.photo_camera, () => onGesture('snapshot')), _GestureButton('Go Home', Icons.home, () => onGesture('home')), _GestureButton('Nod', Icons.smart_toy, () => onGesture('nod'))]), const SizedBox(height: 12), SizedBox(width: double.infinity, height: 40, child: ElevatedButton.icon(onPressed: onCenterHead, icon: const Icon(Icons.center_focus_strong, size: 16), label: Text('Center head', style: GoogleFonts.inter(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: TimoColors.cardTop, foregroundColor: TimoColors.textPrimary, side: const BorderSide(color: TimoColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))))]));
  }
}

class _GestureButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GestureButton(this.label, this.icon, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(decoration: BoxDecoration(color: TimoColors.inset, border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(12)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 24, color: TimoColors.primary), const SizedBox(height: 4), Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500))]))));
  }
}

class _McSlider extends StatefulWidget {
  final double value, min, max;
  final Function(double) onChanged;
  const _McSlider({required this.value, required this.min, required this.max, required this.onChanged});
  @override
  State<_McSlider> createState() => _McSliderState();
}

class _McSliderState extends State<_McSlider> {
  late double _value;
  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: SliderTheme(data: SliderThemeData(trackHeight: 5, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8), overlayShape: const RoundSliderOverlayShape(overlayRadius: 12)), child: Slider(value: _value, min: widget.min, max: widget.max, activeColor: TimoColors.primary, inactiveColor: TimoColors.border, onChanged: (v) {setState(() => _value = v); widget.onChanged(v);})));
  }
}
