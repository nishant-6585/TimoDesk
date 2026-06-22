import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../core/constants.dart';
import '../../../services/spine/spine_provider.dart';
import '../../../services/spine/face_detection_provider.dart';
import '../../../services/spine/visitor_arrived_provider.dart';
import '../../live_feed/widgets/mjpeg_view.dart';
import '../../settings/providers/settings_provider.dart';

// Models
class EventModel {
  final int id;
  final String ago;
  final String type;
  final String details;
  final String session;
  final bool fresh;

  EventModel({
    required this.id,
    required this.ago,
    required this.type,
    required this.details,
    required this.session,
    this.fresh = true,
  });
}

class ToastModel {
  final int id;
  final IconData icon;
  final Color color;
  final String message;

  ToastModel({
    required this.id,
    required this.icon,
    required this.color,
    required this.message,
  });
}

const List<Map<String, dynamic>> INITIAL_EVENTS = [
  {'id': 1, 'ago': '2 sec ago', 'type': 'command_drive', 'details': 'dir: forward', 'session': 'admin', 'fresh': true},
  {'id': 2, 'ago': '5 sec ago', 'type': 'command_head', 'details': 'lr:45 ud:50', 'session': 'admin', 'fresh': true},
  {'id': 4, 'ago': '1 min ago', 'type': 'safety_stop', 'details': 'triggered_by: admin', 'session': 'admin', 'fresh': true},
  {'id': 5, 'ago': '2 min ago', 'type': 'admin_session', 'details': 'connected', 'session': 'system', 'fresh': true},
];

final eventColorMap = {
  'command_drive': const Color(0xFF3B82F6),
  'command_head': const Color(0xFF3B82F6),
  'face_detected': const Color(0xFF4ADE80),
  'visitor_checkin': const Color(0xFF4ADE80),
  'safety_stop': const Color(0xFFEF4444),
  'battery_low': const Color(0xFFF59E0B),
  'snapshot_saved': const Color(0xFFFF6B35),
  'admin_session': const Color(0xFF6B7280),
};

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  double _headLR = 50;
  double _speed = 0.5;
  List<EventModel> _events = [];
  List<ToastModel> _toasts = [];
  int _nextToastId = 0;
  int _nextEventId = 100;
  Timer? _eventTimer;
  Timer? _ageTimer;
  String _timeString = '';

  @override
  void initState() {
    super.initState();
    _events = INITIAL_EVENTS.map((e) => EventModel(
      id: e['id'],
      ago: e['ago'],
      type: e['type'],
      details: e['details'],
      session: e['session'],
      fresh: e['fresh'],
    )).toList();

    _startClockUpdate();
    _startLiveEvents();
    _setupListeners();
  }

  void _setupListeners() {
    ref.listenManual<FaceDetection?>(faceDetectionProvider, (prev, next) {
      if (next == null) return;
      _addEvent({
        'type': 'face_detected',
        'details': next.matched
            ? '${next.name} · L2 ${next.distance.toStringAsFixed(2)}'
            : 'unknown · L2 ${next.distance.toStringAsFixed(2)}',
        'session': 'system',
      });
    });

    ref.listenManual<VisitorArrival?>(visitorArrivedProvider, (prev, next) {
      if (next == null) return;
      _addEvent({
        'type': 'visitor_checkin',
        'details': '${next.visitorName} → ${next.hostName} (${next.channel})',
        'session': 'system',
      });
    });
  }

  void _startLiveEvents() {
    _eventTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final spine = ref.read(spineProvider);
      if (spine.stopped) return;

      // NOTE: face_detected is NOT generated here — real detections are pushed
      // into the feed from the recognizer via ref.listen(faceDetectionProvider).
      final pool = [
        {'type': 'command_head', 'details': 'lr:${30 + (DateTime.now().millisecond % 40)} ud:${40 + (DateTime.now().millisecond % 20)}', 'session': 'admin'},
        {'type': 'command_drive', 'details': 'dir: ${['forward', 'left', 'right', 'back'][DateTime.now().millisecond % 4]}', 'session': 'admin'},
        {'type': 'visitor_checkin', 'details': 'guest #${100 + (DateTime.now().millisecond % 99)}', 'session': 'system'},
      ];
      _addEvent(pool[DateTime.now().millisecond % pool.length]);
    });
  }

  void _startClockUpdate() {
    _updateTimeString();
    _ageTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateTimeString();
    });
  }

  void _updateTimeString() {
    setState(() {
      final now = DateTime.now();
      _timeString = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    });
  }

  void _addEvent(Map<String, dynamic> e) {
    setState(() {
      _events.insert(0, EventModel(
        id: _nextEventId++,
        ago: 'just now',
        type: e['type'],
        details: e['details'],
        session: e['session'],
        fresh: true,
      ));
      if (_events.length > 8) {
        _events.removeLast();
      }
    });
  }

  void _pushToast(IconData icon, Color color, String message) {
    final id = _nextToastId++;
    final toast = ToastModel(id: id, icon: icon, color: color, message: message);
    setState(() => _toasts.add(toast));
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) {
        setState(() => _toasts.removeWhere((t) => t.id == id));
      }
    });
  }

  void _onStop() {
    final spine = ref.read(spineProvider);
    final notifier = ref.read(spineProvider.notifier);
    if (!spine.stopped) {
      notifier.sendIntent({'intent': 'stop'});
      _pushToast(Icons.stop_circle, TimoColors.error, 'Emergency stop engaged');
      _addEvent({'type': 'safety_stop', 'details': 'triggered_by: admin', 'session': 'admin'});
    } else {
      notifier.sendIntent({'intent': 'resume'});
      _pushToast(Icons.check_circle, TimoColors.success, 'Motion re-enabled');
    }
  }

  void _onAction(String id) {
    final notifier = ref.read(spineProvider.notifier);
    switch (id) {
      case 'snapshot':
        notifier.sendIntent({'intent': 'snapshot'});
        _pushToast(Icons.photo_camera, TimoColors.primary, 'Snapshot saved to gallery');
        _addEvent({'type': 'snapshot_saved', 'details': 'gallery/img_0428.jpg', 'session': 'admin'});
        break;
      case 'wave':
        notifier.sendIntent({'intent': 'wave'});
        _pushToast(Icons.waving_hand, TimoColors.primary, 'Timo is waving hello 👋');
        _addEvent({'type': 'command_head', 'details': 'gesture: wave', 'session': 'admin'});
        break;
      case 'home':
        notifier.sendIntent({'intent': 'drive', 'dir': 'home_dock'});
        _pushToast(Icons.home, TimoColors.success, 'Returning to home base');
        _addEvent({'type': 'command_drive', 'details': 'dest: home_dock', 'session': 'admin'});
        break;
      case 'control':
        _pushToast(Icons.sports_esports, TimoColors.primary, 'Opening control room');
        break;
    }
  }

  @override
  void dispose() {
    _eventTimer?.cancel();
    _ageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spineState = ref.watch(spineProvider);
    final online = spineState.connected;
    // Real battery from spine, or null (shown as "—") when unknown — no fake 78.
    final rawBattery = spineState.status?.battery;
    final int? battery = (rawBattery != null && rawBattery >= 0) ? rawBattery : null;
    final stopped = spineState.stopped;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return _buildDesktop(context, online, battery, stopped);
        } else {
          return _buildMobile(context, online, battery, stopped);
        }
      },
    );
  }

  Widget _buildDesktop(BuildContext context, bool online, int? battery, bool stopped) {
    return Scaffold(
      backgroundColor: TimoColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              _McHeader(compact: false, online: online, battery: battery),
              Expanded(
                child: Row(
                  children: [
                    _McSidebar(active: 'dashboard', onNav: (route) {
                      final routes = {
                        'dashboard': '/',
                        'control': '/control',
                        'feed': '/live-feed',
                        'gallery': '/gallery',
                        'events': '/event-log',
                        'patrol_routes': '/patrol-routes',
                        'settings': '/settings',
                      };
                      if (routes.containsKey(route)) {
                        context.go(routes[route]!);
                      }
                    }),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1240),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: _RobotStatusCard(online: online, latency: 12)),
                                    const SizedBox(width: 20),
                                    Expanded(child: _BatteryCard(percent: battery, charging: true)),
                                    const SizedBox(width: 20),
                                    Expanded(child: _VisitorsCard()),
                                    const SizedBox(width: 20),
                                    Expanded(child: _SessionsCard()),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                // Live face-detection card — driven by real recognizer
                                // events, auto-dismisses via faceDetectionProvider.
                                Consumer(
                                  builder: (context, ref, _) {
                                    final det = ref.watch(faceDetectionProvider);
                                    if (det == null) return const SizedBox.shrink();
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 20),
                                      child: _FaceDetectionCard(det: det),
                                    );
                                  },
                                ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: _LiveFeedWidget(stopped: stopped, timeString: _timeString),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      flex: 2,
                                      child: SingleChildScrollView(
                                        child: _QuickControlsPanel(
                                          stopped: stopped,
                                          onStop: _onStop,
                                          onAction: _onAction,
                                          headLR: _headLR,
                                          speed: _speed,
                                          onHeadChange: (v) {
                                            setState(() => _headLR = v);
                                            ref.read(spineProvider.notifier).sendIntent({'intent': 'head', 'lr': v.round(), 'ud': 50});
                                          },
                                          onSpeedChange: (v) {
                                            setState(() => _speed = v);
                                            ref.read(spineProvider.notifier).sendIntent({'intent': 'speed', 'value': v});
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                _EventStreamWidget(events: _events),
                              ],
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
          Positioned(
            bottom: 24,
            right: 24,
            child: _FloatingStopButton(stopped: stopped, onStop: _onStop),
          ),
          _ToastStack(toasts: _toasts),
        ],
      ),
    );
  }

  Widget _buildMobile(BuildContext context, bool online, int? battery, bool stopped) {
    return Scaffold(
      backgroundColor: TimoColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              _McHeader(compact: true, online: online, battery: battery),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _RobotStatusCard(online: online, latency: 12)),
                          const SizedBox(width: 12),
                          Expanded(child: _BatteryCard(percent: battery, charging: true)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _VisitorsCard()),
                          const SizedBox(width: 12),
                          Expanded(child: _SessionsCard()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Consumer(
                        builder: (context, ref, _) {
                          final det = ref.watch(faceDetectionProvider);
                          if (det == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _FaceDetectionCard(det: det),
                          );
                        },
                      ),
                      _LiveFeedWidget(stopped: stopped, timeString: _timeString),
                      const SizedBox(height: 12),
                      _QuickControlsPanel(
                        stopped: stopped,
                        onStop: _onStop,
                        onAction: _onAction,
                        headLR: _headLR,
                        speed: _speed,
                        onHeadChange: (v) {
                          setState(() => _headLR = v);
                          ref.read(spineProvider.notifier).sendIntent({'intent': 'head', 'lr': v.round(), 'ud': 50});
                        },
                        onSpeedChange: (v) {
                          setState(() => _speed = v);
                          ref.read(spineProvider.notifier).sendIntent({'intent': 'speed', 'value': v});
                        },
                      ),
                      const SizedBox(height: 12),
                      _EventStreamWidget(events: _events.take(4).toList()),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 24,
            right: 24,
            child: _FloatingStopButton(stopped: stopped, onStop: _onStop),
          ),
          _ToastStack(toasts: _toasts),
        ],
      ),
    );
  }
}

// All component widgets below
class _McHeader extends StatelessWidget {
  final bool compact;
  final bool online;
  final int? battery; // null = unknown → shown as "—"

  const _McHeader({required this.compact, required this.online, required this.battery});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          // Left: Logo lockup
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [TimoColors.primary, TimoColors.primaryDark],
                ),
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
          // Center: Subtitle (desktop only)
          if (!compact)
            Text(
              'Timo — Reception Robot',
              style: GoogleFonts.inter(fontSize: 13, color: TimoColors.textSecondary),
            ),
          // Right: Status pills and avatar
          Row(children: [
            if (!compact) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: TimoColors.cardTop, border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(battery == null ? Icons.battery_unknown : Icons.battery_charging_full, size: 16,
                      color: battery == null ? TimoColors.textMuted : TimoColors.success),
                  const SizedBox(width: 8),
                  Text(battery == null ? '—' : '$battery%', style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  Container(
                    width: 40,
                    height: 6,
                    decoration: BoxDecoration(color: TimoColors.border, borderRadius: BorderRadius.circular(999)),
                    child: Stack(children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: (40 * (battery ?? 0) / 100).clamp(0, 40),
                          height: 6,
                          decoration: BoxDecoration(color: TimoColors.success, borderRadius: BorderRadius.circular(999)),
                        ),
                      )
                    ]),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (online ? TimoColors.success : TimoColors.error).withOpacity(0.08),
                border: Border.all(color: (online ? TimoColors.success : TimoColors.error).withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: online ? TimoColors.success : TimoColors.error)),
                const SizedBox(width: 8),
                Text(online ? 'ONLINE' : 'OFFLINE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.05, color: online ? TimoColors.success : TimoColors.error)),
              ]),
            ),
            const SizedBox(width: 12),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: TimoColors.border, width: 2), color: const Color(0xFF2A2A2A)),
              child: Center(child: Text('NK', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white))),
            ),
          ]),
        ],
      ),
    );
  }
}

class _McSidebar extends StatelessWidget {
  final String active;
  final Function(String) onNav;

  const _McSidebar({required this.active, required this.onNav});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: TimoColors.surface,
        border: const Border(right: BorderSide(color: TimoColors.border)),
      ),
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _NavItem('Dashboard', Icons.space_dashboard, active == 'dashboard', () => onNav('dashboard')),
              _NavItem('Control', Icons.sports_esports, active == 'control', () => onNav('control')),
              _NavItem('Live Feed', Icons.videocam, active == 'feed', () => onNav('feed')),
              _NavItem('Gallery', Icons.photo_library, active == 'gallery', () => onNav('gallery')),
              _NavItem('Event Log', Icons.receipt_long, active == 'events', () => onNav('events')),
              _NavItem('Patrol Routes', Icons.route, active == 'patrol_routes', () => onNav('patrol_routes')),
              _NavItem('Settings', Icons.settings, active == 'settings', () => onNav('settings')),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: TimoColors.border))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('v0.1.0', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: TimoColors.textMuted)),
            const SizedBox(height: 4),
            Text('xboom · Land Air Water', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF4A4A4A))),
          ]),
        ),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: active ? TimoColors.primary.withOpacity(0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              if (active) Container(width: 4, height: 20, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: TimoColors.primary, borderRadius: BorderRadius.circular(999))),
              Icon(icon, size: 20, color: active ? TimoColors.primary : TimoColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: active ? TimoColors.primary : TimoColors.textSecondary)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RobotStatusCard extends StatelessWidget {
  final bool online;
  final int latency;

  const _RobotStatusCard({required this.online, required this.latency});

  @override
  Widget build(BuildContext context) {
    return _McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('ROBOT STATUS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textSecondary)),
          Icon(Icons.smart_toy, size: 18, color: const Color(0xFF3A3A3A)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: online ? TimoColors.success : TimoColors.error)),
          const SizedBox(width: 12),
          Text(online ? 'ONLINE' : 'OFFLINE', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: online ? TimoColors.success : TimoColors.error)),
        ]),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            text: online ? 'Connected · ' : 'Link lost — retrying…',
            style: GoogleFonts.inter(fontSize: 13, color: TimoColors.textSecondary),
            children: online
                ? [
                    TextSpan(
                      text: '${latency}ms',
                      style: GoogleFonts.jetBrainsMono(fontSize: 13, color: Colors.white),
                    ),
                    TextSpan(
                      text: ' latency',
                      style: GoogleFonts.inter(fontSize: 13, color: TimoColors.textSecondary),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Divider(color: TimoColors.border, height: 1),
        const SizedBox(height: 8),
        Text.rich(TextSpan(
          text: 'Last seen ',
          style: GoogleFonts.inter(fontSize: 11, color: TimoColors.textMuted),
          children: [TextSpan(text: 'just now', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: TimoColors.textMuted))],
        )),
      ]),
    );
  }
}

class _BatteryCard extends StatefulWidget {
  final int? percent; // null = unknown → shown as "—"
  final bool charging;

  const _BatteryCard({required this.percent, required this.charging});

  @override
  State<_BatteryCard> createState() => _BatteryCardState();
}

class _BatteryCardState extends State<_BatteryCard> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: (widget.percent ?? 0).toDouble()).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _animationController.forward();
    });
  }

  @override
  void didUpdateWidget(_BatteryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.percent != widget.percent) {
      _animationController.reset();
      _animation = Tween<double>(begin: _animation.value, end: (widget.percent ?? 0).toDouble()).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
      );
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _McCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('BATTERY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textSecondary)),
          Icon(widget.charging ? Icons.bolt : Icons.battery_full, size: 18, color: TimoColors.primary),
        ]),
        const SizedBox(height: 10),
        Center(
          child: SizedBox(
            width: 104,
            height: 104,
            child: AnimatedBuilder(
              animation: _animation,
              builder