import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../services/spine/spine_provider.dart';

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
  {'id': 1, 'ago': '2 sec ago', 'type': 'command_drive', 'details': 'dir: forward', 'session': 'admin', 'fresh': false},
  {'id': 2, 'ago': '5 sec ago', 'type': 'command_head', 'details': 'lr:45 ud:50', 'session': 'admin', 'fresh': false},
  {'id': 3, 'ago': '12 sec ago', 'type': 'face_detected', 'details': 'confidence: 87%', 'session': 'system', 'fresh': false},
  {'id': 4, 'ago': '1 min ago', 'type': 'safety_stop', 'details': 'triggered_by: admin', 'session': 'admin', 'fresh': false},
  {'id': 5, 'ago': '2 min ago', 'type': 'admin_session', 'details': 'connected', 'session': 'system', 'fresh': false},
  {'id': 6, 'ago': '5 min ago', 'type': 'battery_low', 'details': 'level: 20%', 'session': 'system', 'fresh': false},
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

    _startLiveEvents();
    _startClockUpdate();
  }

  void _startLiveEvents() {
    _eventTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final spine = ref.read(spineProvider);
      if (spine.stopped) return;

      final pool = [
        {'type': 'command_head', 'details': 'lr:${30 + (DateTime.now().millisecond % 40)} ud:${40 + (DateTime.now().millisecond % 20)}', 'session': 'admin'},
        {'type': 'command_drive', 'details': 'dir: ${['forward', 'left', 'right', 'back'][DateTime.now().millisecond % 4]}', 'session': 'admin'},
        {'type': 'face_detected', 'details': 'confidence: ${80 + (DateTime.now().millisecond % 19)}%', 'session': 'system'},
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
    final battery = spineState.status?.battery ?? 78;
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

  Widget _buildDesktop(BuildContext context, bool online, int battery, bool stopped) {
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

  Widget _buildMobile(BuildContext context, bool online, int battery, bool stopped) {
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
  final int battery;

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
                  const Icon(Icons.battery_charging_full, size: 16, color: TimoColors.success),
                  const SizedBox(width: 8),
                  Text('$battery%', style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  Container(
                    width: 40,
                    height: 6,
                    decoration: BoxDecoration(color: TimoColors.border, borderRadius: BorderRadius.circular(999)),
                    child: Stack(children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: (40 * battery / 100).clamp(0, 40),
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
  final int percent;
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
    _animation = Tween<double>(begin: 0, end: widget.percent.toDouble()).animate(
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
      _animation = Tween<double>(begin: _animation.value, end: widget.percent.toDouble()).animate(
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
              builder: (context, child) {
                return CustomPaint(
                  painter: _AnimatedProgressRingPainter(
                    _animation.value,
                    TimoColors.primary,
                    const Color(0xFF2A2A2A),
                    9,
                  ),
                  child: Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('${widget.percent}%', style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.bold, height: 1.0)),
                      const SizedBox(height: 4),
                      Text(widget.charging ? 'Charging' : 'On Battery', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.05, color: TimoColors.textSecondary, height: 1.0)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Divider(color: TimoColors.border, height: 1),
        const SizedBox(height: 10),
        Text.rich(TextSpan(
          text: widget.charging ? 'Full in ' : 'Est. ',
          style: GoogleFonts.inter(fontSize: 11, color: TimoColors.textMuted),
          children: [TextSpan(text: widget.charging ? '~42 min' : '5h 10m remaining', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: TimoColors.textMuted))],
        )),
      ]),
    );
  }
}

class _AnimatedProgressRingPainter extends CustomPainter {
  final double percent;
  final Color color;
  final Color track;
  final double stroke;

  _AnimatedProgressRingPainter(this.percent, this.color, this.track, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final circumference = 2 * 3.14159 * radius;

    // Draw track circle
    canvas.drawCircle(center, radius, Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);

    // Draw progress arc with drop-shadow effect
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // Draw shadow effect
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2,
      (percent / 100) * 2 * 3.14159,
      false,
      Paint()
        ..color = color.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 2
        ..strokeCap = StrokeCap.round,
    );

    // Draw progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2,
      (percent / 100) * 2 * 3.14159,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_AnimatedProgressRingPainter old) => old.percent != percent;
}

class _ProgressRingPainter extends CustomPainter {
  final double percent;
  final Color color;
  final Color track;
  final double stroke;

  _ProgressRingPainter(this.percent, this.color, this.track, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    canvas.drawCircle(center, radius, Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = stroke);

    final progressAngle = (percent / 100) * 2 * 3.14159;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2,
      progressAngle,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) => old.percent != percent;
}

class _VisitorsCard extends StatelessWidget {
  const _VisitorsCard();

  @override
  Widget build(BuildContext context) {
    return _McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('TODAY\'S VISITORS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textSecondary)),
          Icon(Icons.group, size: 18, color: const Color(0xFF3A3A3A)),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('24', style: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('visitors checked in', style: GoogleFonts.inter(fontSize: 13, color: TimoColors.textSecondary)),
            ]),
          ),
          SizedBox(
            width: 110,
            height: 40,
            child: CustomPaint(painter: _SparklinePainter([12, 16, 9, 18, 14, 21, 24], 110, 40, TimoColors.primary), size: const Size(110, 40)),
          ),
        ]),
        const SizedBox(height: 8),
        Divider(color: TimoColors.border, height: 1),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.trending_up, size: 14, color: TimoColors.success),
          const SizedBox(width: 4),
          Text('+3', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: TimoColors.success)),
          const SizedBox(width: 4),
          Text('from yesterday', style: GoogleFonts.inter(fontSize: 11, color: TimoColors.textMuted)),
        ]),
      ]),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final double width;
  final double height;
  final Color color;

  _SparklinePainter(this.data, this.width, this.height, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final max = data.reduce((a, b) => a > b ? a : b);
    final min = data.reduce((a, b) => a < b ? a : b);
    final span = max - min > 0 ? max - min : 1;

    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * width;
      final y = height - 4 - ((data[i] - min) / span) * (height - 8);
      points.add(Offset(x, y));
    }

    final polygonPath = Path();
    polygonPath.moveTo(0, height);
    for (final p in points) polygonPath.lineTo(p.dx, p.dy);
    polygonPath.lineTo(width, height);
    polygonPath.close();

    final gradient = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withOpacity(0.28), color.withOpacity(0)]);
    final shader = gradient.createShader(Rect.fromLTWH(0, 0, width, height));

    canvas.drawPath(polygonPath, Paint()..shader = shader);

    final polylinePath = Path();
    polylinePath.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) polylinePath.lineTo(points[i].dx, points[i].dy);
    canvas.drawPath(polylinePath, Paint()..color = color..strokeWidth = 2..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..style = PaintingStyle.stroke);

    canvas.drawCircle(points[points.length - 1], 2.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.data != data;
}

class _SessionsCard extends StatelessWidget {
  const _SessionsCard();

  @override
  Widget build(BuildContext context) {
    return _McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('ACTIVE SESSIONS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textSecondary)),
          Icon(Icons.hub, size: 18, color: const Color(0xFF3A3A3A)),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('2', style: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('admin sessions active', style: GoogleFonts.inter(fontSize: 13, color: TimoColors.textSecondary)),
            ]),
          ),
          SizedBox(
            width: 50,
            height: 32,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle, color: TimoColors.primary, border: Border.all(color: TimoColors.cardTop, width: 2)), alignment: Alignment.center, child: Text('NK', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
              Positioned(left: 18, child: Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF3B82F6), border: Border.all(color: TimoColors.cardTop, width: 2)), alignment: Alignment.center, child: Text('RS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)))),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Divider(color: TimoColors.border, height: 1),
        const SizedBox(height: 8),
        Text.rich(TextSpan(
          text: 'You ',
          style: GoogleFonts.inter(fontSize: 11, color: TimoColors.textMuted),
          children: [TextSpan(text: '+ 1 other', style: GoogleFonts.inter(fontSize: 11, color: TimoColors.textSecondary))],
        )),
      ]),
    );
  }
}

class _LiveFeedWidget extends StatelessWidget {
  final bool stopped;
  final String timeString;

  const _LiveFeedWidget({required this.stopped, required this.timeString});

  @override
  Widget build(BuildContext context) {
    return _McCard(
      padding: EdgeInsets.zero,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(children: [
          Container(color: Colors.black),
          Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.videocam, size: 56, color: const Color(0xFF3A3A3A)),
              const SizedBox(height: 8),
              Text('Live Feed · 192.168.1.42:8080', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: const Color(0xFF5A5A5A))),
            ]),
          ),
          Positioned(top: 12, left: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), border: Border.all(color: Colors.white.withOpacity(0.05)), borderRadius: BorderRadius.circular(8)), child: Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: TimoColors.error)), const SizedBox(width: 8), Text('LIVE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.15, color: Colors.white))]))),
          if (stopped) Positioned.fill(
            child: Container(
              color: TimoColors.error.withOpacity(0.1),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: TimoColors.error,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stop_circle, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text('MOTION HALTED', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.1, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(bottom: 0, left: 0, right: 0, child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0), Colors.black.withOpacity(0.8)])), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(children: [_Stat('RES', '640×480'), const SizedBox(width: 16), _Stat('FPS', '15', color: TimoColors.success), const SizedBox(width: 16), _Stat('LATENCY', '45ms'), const Spacer(), Text(timeString, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white.withOpacity(0.5)))]),
          )),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Stat(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label.toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.1, color: Colors.white.withOpacity(0.45))),
      const SizedBox(width: 6),
      Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500, color: color ?? Colors.white)),
    ]);
  }
}

class _QuickControlsPanel extends StatelessWidget {
  final bool stopped;
  final VoidCallback onStop;
  final Function(String) onAction;
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
        Text('Quick Actions', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: TimoColors.textPrimary)),
        const SizedBox(height: 16),
        _EmergencyButton(stopped: stopped, onStop: onStop),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.2,
          children: [
            _ActionButton('Control Room', Icons.sports_esports, () => onAction('control')),
            _ActionButton('Wave Hello', Icons.waving_hand, () => onAction('wave')),
            _ActionButton('Take Snapshot', Icons.photo_camera, () => onAction('snapshot')),
            _ActionButton('Go Home', Icons.home, () => onAction('home')),
          ],
        ),
        const SizedBox(height: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('HEAD POSITION', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: TimoColors.textSecondary)),
            Text('LR ${headLR.round()}', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: TimoColors.primary)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Transform.rotate(angle: (headLR - 50) * 0.5 * 3.14159 / 180, child: Icon(Icons.smart_toy, size: 22, color: TimoColors.textSecondary)),
            const SizedBox(width: 12),
            Expanded(child: _McSlider(value: headLR, min: 0, max: 100, onChanged: onHeadChange)),
          ]),
        ]),
        const SizedBox(height: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('SPEED', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: TimoColors.textSecondary)),
            Text('${speed.toStringAsFixed(1)}x', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: TimoColors.primary)),
          ]),
          const SizedBox(height: 8),
          _McSlider(value: speed * 100, min: 30, max: 80, onChanged: (v) => onSpeedChange(v / 100)),
        ]),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.white.withOpacity(0.05),
        child: Container(
          decoration: BoxDecoration(
            color: TimoColors.inset,
            border: Border.all(color: TimoColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: TimoColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmergencyButton extends StatefulWidget {
  final bool stopped;
  final VoidCallback onStop;

  const _EmergencyButton({required this.stopped, required this.onStop});

  @override
  State<_EmergencyButton> createState() => _EmergencyButtonState();
}

class _EmergencyButtonState extends State<_EmergencyButton> with TickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 22, end: 8).animate(CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, _) {
        return GestureDetector(
          onTap: widget.onStop,
          child: Container(
            height: 56,
            width: double.infinity,
            decoration: BoxDecoration(
              color: widget.stopped ? TimoColors.errorPressed : TimoColors.error,
              borderRadius: BorderRadius.circular(12),
              border: widget.stopped ? Border.all(color: TimoColors.error, width: 1.5) : null,
              boxShadow: [
                if (!widget.stopped) BoxShadow(color: TimoColors.error.withOpacity(0.35), blurRadius: _glowAnimation.value),
                BoxShadow(color: TimoColors.error.withOpacity(0.5), blurRadius: 0, spreadRadius: 1.5),
              ],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.stop_circle, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              Text(widget.stopped ? 'MOTION HALTED — RESET' : 'EMERGENCY STOP', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.1, color: Colors.white)),
            ]),
          ),
        );
      },
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
      data: SliderThemeData(
        trackHeight: 5,
        activeTrackColor: TimoColors.primary,
        inactiveTrackColor: TimoColors.border,
        thumbColor: TimoColors.primary,
        overlayColor: TimoColors.primary.withOpacity(0.2),
        thumbShape: const RoundSliderThumbShape(elevation: 4, enabledThumbRadius: 8),
      ),
      child: Slider(value: value, min: min, max: max, onChanged: onChanged),
    );
  }
}

class _EventStreamWidget extends StatelessWidget {
  final List<EventModel> events;

  const _EventStreamWidget({required this.events});

  @override
  Widget build(BuildContext context) {
    return _McCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: TimoColors.success)),
              const SizedBox(width: 8),
              Text('Live Event Stream', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: TimoColors.textPrimary)),
            ]),
            TextButton(
              onPressed: () {},
              child: Row(children: [
                Text('View All', style: GoogleFonts.inter(fontSize: 13, color: TimoColors.primary)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward, size: 15, color: TimoColors.primary),
              ]),
            ),
          ]),
        ),
        const Divider(color: TimoColors.border, height: 1),
        // Table header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(children: [
            SizedBox(width: 120, child: Text('TIME', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textMuted, fontStyle: FontStyle.normal))),
            SizedBox(width: 200, child: Text('EVENT', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textMuted))),
            const SizedBox(width: 24),
            Expanded(child: Text('DETAILS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textMuted))),
            SizedBox(width: 120, child: Text('SESSION', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textMuted))),
          ]),
        ),
        Container(height: 1, color: const Color(0xFF2A2A2A)),
        // Event rows
        ...events.asMap().entries.map((e) {
          final idx = e.key;
          final event = e.value;
          return Container(
            color: idx % 2 == 1 ? Colors.white.withOpacity(0.012) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [
              SizedBox(width: 120, child: Text(event.ago, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: TimoColors.textSecondary))),
              SizedBox(
                width: 200,
                child: _EventChip(event.type),
              ),
              const SizedBox(width: 24),
              Expanded(child: Text(event.details, style: GoogleFonts.jetBrainsMono(fontSize: 13, color: Colors.white.withOpacity(0.85)))),
              SizedBox(
                width: 120,
                child: Row(children: [
                  Icon(event.session == 'admin' ? Icons.person : Icons.memory, size: 14, color: TimoColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(event.session, style: GoogleFonts.inter(fontSize: 12, color: TimoColors.textSecondary)),
                ]),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

class _EventChip extends StatelessWidget {
  final String type;

  const _EventChip(this.type);

  @override
  Widget build(BuildContext context) {
    final color = eventColorMap[type] ?? TimoColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          type,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ]),
    );
  }
}

class _FloatingStopButton extends StatefulWidget {
  final bool stopped;
  final VoidCallback onStop;

  const _FloatingStopButton({required this.stopped, required this.onStop});

  @override
  State<_FloatingStopButton> createState() => _FloatingStopButtonState();
}

class _FloatingStopButtonState extends State<_FloatingStopButton> with TickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 22, end: 8).animate(CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, _) {
        return GestureDetector(
          onTap: widget.onStop,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.stopped ? TimoColors.errorPressed : TimoColors.error,
              boxShadow: [
                if (!widget.stopped) BoxShadow(color: TimoColors.error.withOpacity(0.35), blurRadius: _glowAnimation.value),
                BoxShadow(color: TimoColors.error.withOpacity(0.5), blurRadius: 0, spreadRadius: 1.5),
              ],
            ),
            child: const Icon(Icons.stop, color: Colors.white, size: 28),
          ),
        );
      },
    );
  }
}

class _McCard extends StatelessWidget {
  final Widget child;
  final bool glow;
  final EdgeInsets? padding;

  const _McCard({required this.child, this.glow = false, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [TimoColors.cardTop, TimoColors.cardBottom]),
        border: Border.all(color: TimoColors.border, width: 1),
        borderRadius: BorderRadius.circular(16),
        boxShadow: glow ? [BoxShadow(color: TimoColors.primary.withOpacity(0.10), blurRadius: 20)] : [],
      ),
      child: child,
    );
  }
}

class _ToastStack extends StatelessWidget {
  final List<ToastModel> toasts;

  const _ToastStack({required this.toasts});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 80,
      right: 20,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final toast in toasts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Toast(toast: toast),
          )
      ]),
    );
  }
}

class _Toast extends StatefulWidget {
  final ToastModel toast;

  const _Toast({required this.toast});

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 350), vsync: this);
    _slideAnimation = Tween<Offset>(begin: const Offset(0.3, 0), end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: TimoColors.cardTop,
            border: Border.all(color: widget.toast.color.withOpacity(0.44), width: 1),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.toast.icon, size: 18, color: widget.toast.color),
            const SizedBox(width: 10),
            Text(widget.toast.message, style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withOpacity(0.9))),
          ]),
        ),
      ),
    );
  }
}
