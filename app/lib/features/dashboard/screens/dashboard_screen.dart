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
      _pushToast(Icons.stop_circle, MikeeColors.error, 'Emergency stop engaged');
      _addEvent({'type': 'safety_stop', 'details': 'triggered_by: admin', 'session': 'admin'});
    } else {
      notifier.sendIntent({'intent': 'resume'});
      _pushToast(Icons.check_circle, MikeeColors.success, 'Motion re-enabled');
    }
  }

  void _onAction(String id) {
    final notifier = ref.read(spineProvider.notifier);
    switch (id) {
      case 'snapshot':
        notifier.sendIntent({'intent': 'snapshot'});
        _pushToast(Icons.photo_camera, MikeeColors.primary, 'Snapshot saved to gallery');
        _addEvent({'type': 'snapshot_saved', 'details': 'gallery/img_0428.jpg', 'session': 'admin'});
        break;
      case 'wave':
        notifier.sendIntent({'intent': 'wave'});
        _pushToast(Icons.waving_hand, MikeeColors.primary, 'Mikee is waving hello 👋');
        _addEvent({'type': 'command_head', 'details': 'gesture: wave', 'session': 'admin'});
        break;
      case 'home':
        notifier.sendIntent({'intent': 'drive', 'dir': 'home_dock'});
        _pushToast(Icons.home, MikeeColors.success, 'Returning to home base');
        _addEvent({'type': 'command_drive', 'details': 'dest: home_dock', 'session': 'admin'});
        break;
      case 'control':
        _pushToast(Icons.sports_esports, MikeeColors.primary, 'Opening control room');
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
      backgroundColor: MikeeColors.background,
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
      backgroundColor: MikeeColors.background,
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
        color: MikeeColors.surface.withOpacity(0.8),
        border: const Border(bottom: BorderSide(color: MikeeColors.border)),
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
                  colors: [MikeeColors.primary, MikeeColors.primaryDark],
                ),
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
          // Center: Subtitle (desktop only)
          if (!compact)
            Text(
              'Mikee — Reception Robot',
              style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary),
            ),
          // Right: Status pills and avatar
          Row(children: [
            if (!compact) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: MikeeColors.cardTop, border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(battery == null ? Icons.battery_unknown : Icons.battery_charging_full, size: 16,
                      color: battery == null ? MikeeColors.textMuted : MikeeColors.success),
                  const SizedBox(width: 8),
                  Text(battery == null ? '—' : '$battery%', style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  Container(
                    width: 40,
                    height: 6,
                    decoration: BoxDecoration(color: MikeeColors.border, borderRadius: BorderRadius.circular(999)),
                    child: Stack(children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: (40 * (battery ?? 0) / 100).clamp(0, 40),
                          height: 6,
                          decoration: BoxDecoration(color: MikeeColors.success, borderRadius: BorderRadius.circular(999)),
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
                color: (online ? MikeeColors.success : MikeeColors.error).withOpacity(0.08),
                border: Border.all(color: (online ? MikeeColors.success : MikeeColors.error).withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: online ? MikeeColors.success : MikeeColors.error)),
                const SizedBox(width: 8),
                Text(online ? 'ONLINE' : 'OFFLINE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.05, color: online ? MikeeColors.success : MikeeColors.error)),
              ]),
            ),
            const SizedBox(width: 12),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: MikeeColors.border, width: 2), color: const Color(0xFF2A2A2A)),
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
        color: MikeeColors.surface,
        border: const Border(right: BorderSide(color: MikeeColors.border)),
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
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: MikeeColors.border))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('v0.1.0', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: MikeeColors.textMuted)),
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
              color: active ? MikeeColors.primary.withOpacity(0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              if (active) Container(width: 4, height: 20, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: MikeeColors.primary, borderRadius: BorderRadius.circular(999))),
              Icon(icon, size: 20, color: active ? MikeeColors.primary : MikeeColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: active ? MikeeColors.primary : MikeeColors.textSecondary)),
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
          Text('ROBOT STATUS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
          Icon(Icons.smart_toy, size: 18, color: const Color(0xFF3A3A3A)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: online ? MikeeColors.success : MikeeColors.error)),
          const SizedBox(width: 12),
          Text(online ? 'ONLINE' : 'OFFLINE', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: online ? MikeeColors.success : MikeeColors.error)),
        ]),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            text: online ? 'Connected · ' : 'Link lost — retrying…',
            style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary),
            children: online
                ? [
                    TextSpan(
                      text: '${latency}ms',
                      style: GoogleFonts.jetBrainsMono(fontSize: 13, color: Colors.white),
                    ),
                    TextSpan(
                      text: ' latency',
                      style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Divider(color: MikeeColors.border, height: 1),
        const SizedBox(height: 8),
        Text.rich(TextSpan(
          text: 'Last seen ',
          style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted),
          children: [TextSpan(text: 'just now', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: MikeeColors.textMuted))],
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
          Text('BATTERY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
          Icon(widget.charging ? Icons.bolt : Icons.battery_full, size: 18, color: MikeeColors.primary),
        ]),
        const SizedBox(height: 10),
        Center(
          child: SizedBox(
            width: 104,
            height: 104,
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, _) {
                final double value = widget.percent == null ? 0 : _animation.value;
                final Color ringColor = widget.percent == null
                    ? MikeeColors.textMuted
                    : value <= 20
                        ? MikeeColors.error
                        : value <= 40
                            ? MikeeColors.warning
                            : MikeeColors.success;
                return CustomPaint(
                  painter: _BatteryRingPainter(progress: value / 100, color: ringColor),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.percent == null ? '—' : '${value.round()}%',
                          style: GoogleFonts.jetBrainsMono(fontSize: 22, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary),
                        ),
                        Text(
                          widget.charging ? 'charging' : 'on battery',
                          style: GoogleFonts.inter(fontSize: 10, color: MikeeColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text.rich(TextSpan(
          text: 'Est. runtime ',
          style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted),
          children: [
            TextSpan(
              text: widget.percent == null ? '—' : '~${(widget.percent! * 4.2).round()} min',
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: MikeeColors.textSecondary),
            ),
          ],
        )),
      ]),
    );
  }
}

/// Circular battery gauge painted behind the percentage readout.
class _BatteryRingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;

  _BatteryRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 6;
    final track = Paint()
      ..color = MikeeColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.1415926535 / 2,
      2 * 3.1415926535 * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_BatteryRingPainter old) => old.progress != progress || old.color != color;
}

/// Shared card container — gradient surface, hairline border, rounded corners.
class _McCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _McCard({required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MikeeColors.cardTop, MikeeColors.cardBottom],
        ),
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

/// Small stat card: today's visitor check-ins.
class _VisitorsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('VISITORS TODAY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
          Icon(Icons.people_alt, size: 18, color: const Color(0xFF3A3A3A)),
        ]),
        const SizedBox(height: 12),
        Text('12', style: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary)),
        const SizedBox(height: 4),
        Text('check-ins since 9:00', style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textMuted)),
      ]),
    );
  }
}

/// Small stat card: active admin/control sessions.
class _SessionsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('ACTIVE SESSIONS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
          Icon(Icons.hub, size: 18, color: const Color(0xFF3A3A3A)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text('1', style: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.bold, color: MikeeColors.primary)),
          const SizedBox(width: 6),
          Text('admin', style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
        ]),
        const SizedBox(height: 4),
        Text('this device', style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textMuted)),
      ]),
    );
  }
}

/// Live face-recognition banner — driven by [faceDetectionProvider] events.
class _FaceDetectionCard extends StatelessWidget {
  final FaceDetection det;

  const _FaceDetectionCard({required this.det});

  @override
  Widget build(BuildContext context) {
    final matched = det.matched;
    final accent = matched ? MikeeColors.success : MikeeColors.warning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.06),
        border: Border.all(color: accent.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withOpacity(0.15)),
          child: Icon(matched ? Icons.how_to_reg : Icons.person_search, color: accent, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              matched ? det.name : 'Unknown visitor',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              '${matched ? 'Recognized' : 'No match'} · L2 ${det.distance.toStringAsFixed(2)}',
              style: GoogleFonts.jetBrainsMono(fontSize: 12, color: MikeeColors.textSecondary),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: Text(matched ? 'MATCH' : 'CHECK', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05, color: accent)),
        ),
      ]),
    );
  }
}

/// Live MJPEG camera feed with a status overlay. Reads the robot IP from settings.
class _LiveFeedWidget extends ConsumerWidget {
  final bool stopped;
  final String timeString;

  const _LiveFeedWidget({required this.stopped, required this.timeString});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotIp = ref.watch(settingsProvider).robotIp;
    return _McCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              const Icon(Icons.videocam, size: 16, color: MikeeColors.primary),
              const SizedBox(width: 8),
              Text('LIVE FEED', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
            ]),
            Text(timeString, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: MikeeColors.textMuted)),
          ]),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              Container(
                color: Colors.black,
                child: MjpegView(url: robotStreamUrl(robotIp)),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 7, height: 7, decoration: const BoxDecoration(shape: BoxShape.circle, color: MikeeColors.error)),
                    const SizedBox(width: 6),
                    Text('LIVE', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.1, color: Colors.white)),
                  ]),
                ),
              ),
              if (stopped)
                Container(
                  color: Colors.black.withOpacity(0.55),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.stop_circle, color: MikeeColors.error, size: 40),
                      const SizedBox(height: 8),
                      Text('MOTION STOPPED', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.08, color: Colors.white)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Right-hand control panel: quick actions, head/speed sliders, STOP.
class _QuickControlsPanel extends StatelessWidget {
  final bool stopped;
  final VoidCallback onStop;
  final void Function(String) onAction;
  final double headLR;
  final double speed;
  final ValueChanged<double> onHeadChange;
  final ValueChanged<double> onSpeedChange;

  const _QuickControlsPanel({
    required this.stopped,
    required this.onStop,
    required this.onAction,
    required this.headLR,
    required this.speed,
    required this.onHeadChange,
    required this.onSpeedChange,
  });

  @override
  Widget build(BuildContext context) {
    return _McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('QUICK CONTROLS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _ActionButton(icon: Icons.photo_camera, label: 'Snapshot', onTap: stopped ? null : () => onAction('snapshot'))),
          const SizedBox(width: 10),
          Expanded(child: _ActionButton(icon: Icons.waving_hand, label: 'Wave', onTap: stopped ? null : () => onAction('wave'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _ActionButton(icon: Icons.home, label: 'Home', onTap: stopped ? null : () => onAction('home'))),
          const SizedBox(width: 10),
          Expanded(child: _ActionButton(icon: Icons.sports_esports, label: 'Control', onTap: () => onAction('control'))),
        ]),
        const SizedBox(height: 18),
        _SliderRow(label: 'Head L/R', value: headLR, min: 0, max: 100, suffix: headLR.round().toString(), enabled: !stopped, onChanged: onHeadChange),
        const SizedBox(height: 12),
        _SliderRow(label: 'Speed', value: speed, min: 0, max: 1, suffix: '${(speed * 100).round()}%', enabled: !stopped, onChanged: onSpeedChange),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: Material(
            color: stopped ? MikeeColors.success : MikeeColors.error,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onStop,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(stopped ? Icons.play_arrow : Icons.stop, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(stopped ? 'RESUME MOTION' : 'EMERGENCY STOP', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.05, color: Colors.white)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: MikeeColors.inset,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Icon(icon, size: 20, color: disabled ? MikeeColors.textMuted : MikeeColors.primary),
            const SizedBox(height: 6),
            Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: disabled ? MikeeColors.textMuted : MikeeColors.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textSecondary)),
        Text(suffix, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: enabled ? MikeeColors.textPrimary : MikeeColors.textMuted)),
      ]),
      SliderTheme(
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
          onChanged: enabled ? onChanged : null,
        ),
      ),
    ]);
  }
}

/// Recent-events list shown on the dashboard.
class _EventStreamWidget extends StatelessWidget {
  final List<EventModel> events;

  const _EventStreamWidget({required this.events});

  @override
  Widget build(BuildContext context) {
    return _McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('EVENT STREAM', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: MikeeColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
            child: Text('LIVE', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: MikeeColors.success)),
          ),
        ]),
        const SizedBox(height: 12),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No recent events', style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textMuted)),
          )
        else
          ...events.map((e) {
            final color = eventColorMap[e.type] ?? MikeeColors.textMuted;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(margin: const EdgeInsets.only(top: 5), width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.type, style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w500, color: MikeeColors.textPrimary)),
                    Text(e.details, style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textSecondary)),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(e.ago, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: MikeeColors.textMuted)),
                  Text(e.session, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF4A4A4A))),
                ]),
              ]),
            );
          }),
      ]),
    );
  }
}

/// Circular STOP / RESUME button anchored bottom-right.
class _FloatingStopButton extends StatelessWidget {
  final bool stopped;
  final VoidCallback onStop;

  const _FloatingStopButton({required this.stopped, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final color = stopped ? MikeeColors.success : MikeeColors.error;
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: color.withOpacity(0.5),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onStop,
        child: SizedBox(
          width: 60,
          height: 60,
          child: Icon(stopped ? Icons.play_arrow : Icons.stop, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}

/// Transient toast overlay stacked at the bottom-left of the screen.
class _ToastStack extends StatelessWidget {
  final List<ToastModel> toasts;

  const _ToastStack({required this.toasts});

  @override
  Widget build(BuildContext context) {
    if (toasts.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 24,
      bottom: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: toasts.map((t) {
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: MikeeColors.cardTop,
                border: Border.all(color: t.color.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 16)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(t.icon, size: 18, color: t.color),
                const SizedBox(width: 10),
                Text(t.message, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: MikeeColors.textPrimary)),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}