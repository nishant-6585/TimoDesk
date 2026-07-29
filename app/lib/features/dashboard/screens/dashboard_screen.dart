import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/spine_base.dart';
import '../../../core/theme.dart';
import '../../../core/constants.dart';
import '../../../services/spine/spine_provider.dart';
import '../../navigation/providers/nav_points_provider.dart';
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
  // Desktop/Mobile preview toggle (matches the prototype's floating pill).
  bool _forceMobile = false;

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

  bool _recording = false;
  bool _patrolling = false;

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
        notifier.sendIntent({'intent': 'dock'});
        _pushToast(Icons.battery_charging_full, MikeeColors.success, 'Returning to charging dock');
        _addEvent({'type': 'command_dock', 'details': 'auto-dock + charge', 'session': 'admin'});
        break;
      case 'stop_voice':
        // Remotely end the robot's active listening/voice session (spine relays
        // it to the robot app, which closes the ElevenLabs session).
        notifier.sendIntent({'intent': 'stop_voice'});
        _pushToast(Icons.mic_off, MikeeColors.error, 'Stopped the robot\'s mic / listening');
        _addEvent({'type': 'command_voice', 'details': 'admin stopped mic', 'session': 'admin'});
        break;
      case 'record':
        final starting = !_recording;
        setState(() => _recording = starting);
        http
            .post(Uri.parse('$spineHttpBase/record/${starting ? 'start' : 'stop'}'))
            .then((r) {
          if (r.statusCode != 200 && mounted) setState(() => _recording = !starting);
        }).catchError((_) {
          if (mounted) setState(() => _recording = !starting);
        });
        _pushToast(Icons.videocam, starting ? MikeeColors.error : MikeeColors.success,
            starting ? 'Recording started' : 'Recording saved on spine (recordings/)');
        _addEvent({'type': 'video_record', 'details': starting ? 'start' : 'stop', 'session': 'admin'});
        break;
      case 'control':
        context.go('/control');
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
    // ONLINE means the ROBOT is reachable, not merely the browser↔spine link —
    // same derivation as the Navigation screen so the two never disagree.
    final online = spineState.connected && (spineState.status?.online ?? false);
    // Real battery from spine, or null (shown as "—") when unknown — no fake value.
    final rawBattery = spineState.status?.battery;
    final int? battery = (rawBattery != null && rawBattery >= 0) ? rawBattery : null;
    final bool charging = spineState.status?.isCharging ?? false;
    final stopped = spineState.stopped;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = !_forceMobile && constraints.maxWidth >= 900;
        return Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.all(wide ? 24 : 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStatCards(wide, online, battery, charging),
                      SizedBox(height: wide ? 20 : 12),
                      Consumer(
                        builder: (context, ref, _) {
                          final det = ref.watch(faceDetectionProvider);
                          if (det == null) return const SizedBox.shrink();
                          return Padding(
                            padding: EdgeInsets.only(bottom: wide ? 20 : 12),
                            child: _FaceDetectionCard(det: det),
                          );
                        },
                      ),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: _LiveFeedWidget(stopped: stopped, timeString: _timeString)),
                            const SizedBox(width: 20),
                            Expanded(flex: 2, child: _quickActions(stopped)),
                          ],
                        )
                      else ...[
                        _LiveFeedWidget(stopped: stopped, timeString: _timeString),
                        const SizedBox(height: 12),
                        _quickActions(stopped),
                      ],
                      SizedBox(height: wide ? 20 : 12),
                      _EventStreamWidget(events: wide ? _events : _events.take(4).toList()),
                      const SizedBox(height: 88),
                    ],
                  ),
                ),
              ),
            ),
            // Floating Desktop/Mobile preview toggle (prototype parity).
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: _DesktopMobileToggle(
                  mobile: _forceMobile,
                  onChanged: (m) => setState(() => _forceMobile = m),
                ),
              ),
            ),
            Positioned(
              bottom: 24,
              right: 24,
              child: _FloatingStopButton(stopped: stopped, onStop: _onStop),
            ),
            _ToastStack(toasts: _toasts),
          ],
        );
      },
    );
  }

  Widget _buildStatCards(bool wide, bool online, int? battery, bool charging) {
    final cards = <Widget>[
      _RobotStatusCard(online: online, latency: 12),
      _BatteryCard(percent: battery, charging: charging),
      _VisitorsCard(),
      _SessionsCard(),
    ];
    if (wide) {
      // IntrinsicHeight + stretch → all four cards take the tallest one's height.
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 20),
              Expanded(child: cards[i]),
            ]
          ],
        ),
      );
    }
    return Column(children: [
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
      ),
      const SizedBox(height: 12),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
      ),
    ]);
  }

  Widget _quickActions(bool stopped) {
    return Column(children: [
      _quickActionsPanelOnly(stopped),
      const SizedBox(height: 16),
      _navPointsCard(stopped),
    ]);
  }

  /// Saved navigation points + patrol — live from the shared provider, so
  /// newly captured points appear here immediately.
  Widget _navPointsCard(bool stopped) {
    final pointsAsync = ref.watch(navPointsProvider);
    final points = pointsAsync.valueOrNull ?? const <NavPoint>[];
    return _McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Navigation Points',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          SizedBox(
            height: 32,
            child: ElevatedButton.icon(
              onPressed: (stopped || points.length < 2)
                  ? null
                  : () {
                      final n = ref.read(navPointsProvider.notifier);
                      if (_patrolling) {
                        n.patrolStop();
                        _pushToast(Icons.route, MikeeColors.success, 'Patrol stopped');
                      } else {
                        n.patrolStart(points);
                        _pushToast(Icons.route, MikeeColors.primary,
                            'Patrolling ${points.length} points');
                      }
                      setState(() => _patrolling = !_patrolling);
                    },
              icon: Icon(_patrolling ? Icons.stop : Icons.route, size: 14),
              label: Text(_patrolling ? 'Stop patrol' : 'Patrol',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _patrolling ? MikeeColors.error : MikeeColors.inset,
                foregroundColor:
                    _patrolling ? Colors.white : MikeeColors.textPrimary,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        if (points.isEmpty)
          Text('No saved points yet — capture them on the Navigation screen.',
              style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textMuted))
        else
          ...points.map((pt) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.place, size: 15, color: MikeeColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(pt.name,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 13, color: MikeeColors.textPrimary))),
                  SizedBox(
                    height: 28,
                    child: TextButton.icon(
                      onPressed: stopped
                          ? null
                          : () {
                              ref.read(navPointsProvider.notifier).goTo(pt);
                              _pushToast(Icons.navigation, MikeeColors.primary,
                                  'Going to "${pt.name}"');
                            },
                      icon: const Icon(Icons.navigation, size: 13),
                      label: Text('Go',
                          style: GoogleFonts.inter(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              )),
      ]),
    );
  }

  Widget _quickActionsPanelOnly(bool stopped) {
    return _QuickActionsPanel(
      stopped: stopped,
      recording: _recording,
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
    );
  }
}

// ───────────────────────────── Shared card ─────────────────────────────

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

Widget _cardLabel(String text) => Text(
      text,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary),
    );

// ───────────────────────────── Stat cards ─────────────────────────────

class _RobotStatusCard extends StatelessWidget {
  final bool online;
  final int latency;

  const _RobotStatusCard({required this.online, required this.latency});

  @override
  Widget build(BuildContext context) {
    return _McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _cardLabel('ROBOT STATUS'),
          const Icon(Icons.smart_toy, size: 18, color: Color(0xFF3A3A3A)),
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
            text: online ? 'Connected · ' : 'Robot unreachable — check power/Wi-Fi',
            style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary),
            children: online
                ? [
                    TextSpan(text: '${latency}ms', style: GoogleFonts.jetBrainsMono(fontSize: 13, color: Colors.white)),
                    TextSpan(text: ' latency', style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(color: MikeeColors.border, height: 1),
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
    _animationController = AnimationController(duration: const Duration(milliseconds: 1100), vsync: this);
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
          _cardLabel('BATTERY'),
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
                            : MikeeColors.primary;
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
                          widget.charging ? 'CHARGING' : 'ON BATTERY',
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: MikeeColors.textMuted),
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
          text: widget.charging ? 'Full in ' : 'Est. runtime ',
          style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted),
          children: [
            TextSpan(
              text: widget.percent == null ? '—' : '~${((100 - widget.percent!) * 1.9).round()} min',
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

class _VisitorsCard extends StatelessWidget {
  // No live data source yet — representative figures matching the prototype.
  static const int _count = 24;
  static const int _delta = 3;
  static const List<double> _trend = [0.35, 0.28, 0.5, 0.42, 0.62, 0.55, 0.8, 1.0];

  @override
  Widget build(BuildContext context) {
    return _McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _cardLabel("TODAY'S VISITORS"),
          const Icon(Icons.people_alt, size: 18, color: Color(0xFF3A3A3A)),
        ]),
        const SizedBox(height: 12),
        Text('$_count', style: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary, height: 1.0)),
        const SizedBox(height: 4),
        Text('visitors checked in', style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textMuted)),
        const SizedBox(height: 10),
        SizedBox(height: 32, child: CustomPaint(size: const Size(double.infinity, 32), painter: _SparklinePainter(_trend))),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.trending_up, size: 14, color: MikeeColors.success),
          const SizedBox(width: 4),
          Text('+$_delta from yesterday', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: MikeeColors.success)),
        ]),
      ]),
    );
  }
}

/// Tiny line+fill sparkline used by the visitors card.
class _SparklinePainter extends CustomPainter {
  final List<double> points; // each 0..1

  _SparklinePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final dx = size.width / (points.length - 1);
    Offset at(int i) => Offset(dx * i, size.height - points[i] * size.height);

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MikeeColors.primary.withOpacity(0.25), MikeeColors.primary.withOpacity(0.0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = MikeeColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.points != points;
}

class _SessionsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _McCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _cardLabel('ACTIVE SESSIONS'),
          const Icon(Icons.share, size: 18, color: Color(0xFF3A3A3A)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text('2', style: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary, height: 1.0)),
          const Spacer(),
          SizedBox(
            width: 54,
            height: 28,
            child: Stack(children: [
              const _SessionAvatar(initials: 'RS', color: MikeeColors.info, left: 26),
              const _SessionAvatar(initials: 'NK', color: MikeeColors.primary, left: 0),
            ]),
          ),
        ]),
        const SizedBox(height: 4),
        Text('admin sessions active', style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textMuted)),
        const SizedBox(height: 10),
        Text('You + 1 other', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF4A4A4A))),
      ]),
    );
  }
}

class _SessionAvatar extends StatelessWidget {
  final String initials;
  final Color color;
  final double left;

  const _SessionAvatar({required this.initials, required this.color, required this.left});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: MikeeColors.cardBottom, width: 2),
        ),
        child: Center(child: Text(initials, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white))),
      ),
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
            Text(matched ? det.name : 'Unknown visitor', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary)),
            const SizedBox(height: 2),
            Text('${matched ? 'Recognized' : 'No match'} · L2 ${det.distance.toStringAsFixed(2)}', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: MikeeColors.textSecondary)),
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

// ───────────────────────────── Live feed ─────────────────────────────

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
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              // Black background + empty-state hint, shown until the stream paints over them.
              Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.videocam, size: 56, color: Color(0xFF2E2E2E)),
                  const SizedBox(height: 8),
                  Text('Live Feed · $robotIp:$robotCameraPort', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: const Color(0xFF3A3A3A))),
                ]),
              ),
              // The live MJPEG stream paints on top of the placeholder once frames arrive.
              Positioned.fill(child: MjpegView(url: robotStreamUrl(robotIp))),
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
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.fullscreen, size: 18, color: Colors.white70),
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
        const SizedBox(height: 10),
        Row(children: [
          _feedStat('RES', '640×480'),
          const SizedBox(width: 18),
          _feedStat('FPS', '15'),
          const SizedBox(width: 18),
          _feedStat('LATENCY', '45ms'),
          const Spacer(),
          Text(timeString, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: MikeeColors.textMuted)),
        ]),
      ]),
    );
  }

  Widget _feedStat(String label, String value) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label ', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: MikeeColors.textMuted)),
      Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: MikeeColors.textSecondary)),
    ]);
  }
}

// ───────────────────────────── Quick actions ─────────────────────────────

class _QuickActionsPanel extends StatelessWidget {
  final bool stopped;
  final bool recording;
  final VoidCallback onStop;
  final void Function(String) onAction;
  final double headLR;
  final double speed;
  final ValueChanged<double> onHeadChange;
  final ValueChanged<double> onSpeedChange;

  const _QuickActionsPanel({
    required this.stopped,
    required this.recording,
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
        Text('Quick Actions', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary)),
        const SizedBox(height: 16),
        // Emergency stop — primary, glowing, at the top.
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: stopped ? [] : [BoxShadow(color: MikeeColors.error.withOpacity(0.45), blurRadius: 22)],
            ),
            child: Material(
              color: stopped ? MikeeColors.success : MikeeColors.error,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onStop,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(stopped ? Icons.play_arrow : Icons.stop_circle, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Text(stopped ? 'RESUME MOTION' : 'EMERGENCY STOP', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.05, color: Colors.white)),
                  ]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Stop the robot's mic / listening remotely (works even under STOP).
        Row(children: [
          Expanded(child: _ActionButton(icon: Icons.mic_off, label: 'Stop Mic / Listening', onTap: () => onAction('stop_voice'))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _ActionButton(icon: Icons.sports_esports, label: 'Control Room', onTap: () => onAction('control'))),
          const SizedBox(width: 12),
          Expanded(child: _ActionButton(icon: Icons.waving_hand, label: 'Wave Hello', onTap: stopped ? null : () => onAction('wave'))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _ActionButton(icon: Icons.photo_camera, label: 'Take Snapshot', onTap: stopped ? null : () => onAction('snapshot'))),
          const SizedBox(width: 12),
          Expanded(child: _ActionButton(icon: Icons.battery_charging_full, label: 'Go to Charge', onTap: stopped ? null : () => onAction('home'))),
          const SizedBox(width: 10),
          Expanded(child: _ActionButton(icon: Icons.videocam, label: recording ? 'Stop Rec' : 'Record', onTap: () => onAction('record'))),
        ]),
        const SizedBox(height: 20),
        _SliderRow(label: 'HEAD POSITION', value: headLR, min: 0, max: 100, suffix: 'LR ${headLR.round()}', leading: Icons.smart_toy, enabled: !stopped, onChanged: onHeadChange),
        const SizedBox(height: 14),
        _SliderRow(label: 'SPEED', value: speed, min: 0, max: 1, suffix: '${speed.toStringAsFixed(1)}x', enabled: !stopped, onChanged: onSpeedChange),
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
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: disabled ? MikeeColors.textMuted : MikeeColors.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: disabled ? MikeeColors.textMuted : MikeeColors.textSecondary),
              ),
            ),
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
  final IconData? leading;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.enabled,
    required this.onChanged,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: MikeeColors.textSecondary)),
        Text(suffix, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: enabled ? MikeeColors.primary : MikeeColors.textMuted)),
      ]),
      Row(children: [
        if (leading != null) ...[
          Icon(leading, size: 16, color: MikeeColors.textMuted),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: SliderTheme(
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
        ),
      ]),
    ]);
  }
}

// ───────────────────────────── Event stream ─────────────────────────────

/// Recent-events table shown on the dashboard.
class _EventStreamWidget extends StatelessWidget {
  final List<EventModel> events;

  const _EventStreamWidget({required this.events});

  @override
  Widget build(BuildContext context) {
    return _McCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: MikeeColors.success)),
            const SizedBox(width: 8),
            Text('Live Event Stream', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary)),
          ]),
          Text('View All →', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: MikeeColors.primary)),
        ]),
        const SizedBox(height: 16),
        // Column headers
        Row(children: [
          _col('TIME', 2),
          _col('EVENT', 3),
          _col('DETAILS', 4),
          _col('SESSION', 2, alignEnd: true),
        ]),
        const SizedBox(height: 8),
        const Divider(color: MikeeColors.border, height: 1),
        const SizedBox(height: 4),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No recent events', style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textMuted)),
          )
        else
          ...events.map((e) {
            final color = eventColorMap[e.type] ?? MikeeColors.textMuted;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(flex: 2, child: Text(e.ago, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: MikeeColors.textMuted))),
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                        const SizedBox(width: 6),
                        Flexible(child: Text(e.type, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500, color: color))),
                      ]),
                    ),
                  ),
                ),
                Expanded(flex: 4, child: Text(e.details, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: MikeeColors.textSecondary))),
                Expanded(
                  flex: 2,
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    const Icon(Icons.person, size: 12, color: MikeeColors.textMuted),
                    const SizedBox(width: 4),
                    Text(e.session, style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted)),
                  ]),
                ),
              ]),
            );
          }),
      ]),
    );
  }

  Widget _col(String label, int flex, {bool alignEnd = false}) {
    return Expanded(
      flex: flex,
      child: Align(
        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: MikeeColors.textMuted)),
      ),
    );
  }
}

// ───────────────────────────── Floating controls ─────────────────────────────

/// Desktop/Mobile layout preview toggle pill (matches the prototype).
class _DesktopMobileToggle extends StatelessWidget {
  final bool mobile;
  final ValueChanged<bool> onChanged;

  const _DesktopMobileToggle({required this.mobile, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MikeeColors.cardTop,
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 16)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _seg('Desktop', Icons.desktop_windows, !mobile, () => onChanged(false)),
        _seg('Mobile', Icons.smartphone, mobile, () => onChanged(true)),
      ]),
    );
  }

  Widget _seg(String label, IconData icon, bool active, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: active ? MikeeColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: active ? Colors.white : MikeeColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : MikeeColors.textSecondary)),
          ]),
        ),
      ),
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
