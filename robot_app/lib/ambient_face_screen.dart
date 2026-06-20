import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'app_widgets.dart';
import 'face_painter.dart';
import 'face_rig.dart';
import 'gaze_tracker.dart';
import 'services/spine_client.dart';
import 'dashboard_screen.dart';

/// The robot's front-of-house home: an ambient animated face (Beam/OLED
/// CustomPainter, #82). #82 P2 wires it to live perception:
///   • LOCAL ML Kit on /snapshot → gaze x/y + presence → attentive (anonymous).
///   • SPINE WS face_detected → greeting-by-name (authoritative identity).
///   • CSJBot personDetected → coarse presence fallback.
/// Plus a debug-only voice-state cycler (stand-in for #80 until voice lands).
/// Tap anywhere → Dashboard.
class AmbientFaceScreen extends ConsumerStatefulWidget {
  const AmbientFaceScreen({super.key});

  @override
  ConsumerState<AmbientFaceScreen> createState() => _AmbientFaceScreenState();
}

class _AmbientFaceScreenState extends ConsumerState<AmbientFaceScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  FaceState _face = const FaceState();
  final FaceRig _rig = FaceRig();
  final _repaint = _FaceRepaint(); // per-frame repaint signal for the painter

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  // ── Live perception (Wire 1 + Wire 2) ──────────────────────────────────────
  final GazeTracker _gaze = GazeTracker();
  final SpineClient _spine = SpineClient();
  StreamSubscription<GazeResult>? _gazeSub;
  StreamSubscription<FaceDetectedEvent>? _faceSub;
  StreamSubscription<bool>? _presenceSub;

  bool _useLivePerception = true; // toggle in debug card; drives gaze when on
  bool _present = false; // a face box is currently visible
  double _liveGazeX = 0, _liveGazeY = 0;
  Timer? _presenceHold;

  // Greeting overlay (Wire 2).
  String? _greetName;
  bool _greetVisible = false;
  Timer? _greetTimer;
  final Map<String, DateTime> _greetedAt = {}; // 10-min re-greet debounce

  // Voice cycle demo (Wire 3, debug only).
  bool _voiceActive = false;
  int _voiceCycleId = 0;
  final List<Timer> _voiceTimers = [];

  static const Duration _greetHold = Duration(milliseconds: 3500);
  static const Duration _regreetWindow = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();

    // Live perception streams.
    _gazeSub = _gaze.results.listen(_onGaze);
    _faceSub = _spine.faceDetected.listen(_onFaceDetected);
    _presenceSub = _spine.personDetected.listen(_onPersonDetected);
    _gaze.start();
    _spine.start();

    // Preserve old behavior: bring up the control WS servers (:8081-3) if the
    // camera is already streaming when we mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(streamProvider).isStreaming) _startControlServers();
    });
  }

  void _startControlServers() {
    if (!ref.read(headProvider).isRunning) ref.read(headProvider.notifier).startHeadControl();
    if (!ref.read(chassisProvider).isRunning) ref.read(chassisProvider.notifier).startChassisControl();
    if (!ref.read(armProvider).isRunning) ref.read(armProvider.notifier).startArmControl();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _presenceHold?.cancel();
    _greetTimer?.cancel();
    for (final t in _voiceTimers) {
      t.cancel();
    }
    _gazeSub?.cancel();
    _faceSub?.cancel();
    _presenceSub?.cancel();
    _gaze.dispose();
    _spine.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause the /snapshot poll when backgrounded (CPU); keep the WS (cheap).
    if (state == AppLifecycleState.resumed) {
      _gaze.start();
    } else {
      _gaze.stop();
    }
  }

  // ── Frame loop ──────────────────────────────────────────────────────────────
  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;
    final follow = _useLivePerception && _present;
    _rig.tick(
      _face,
      dt,
      followGx: follow ? _liveGazeX : null,
      followGy: follow ? _liveGazeY : null,
    );
    _repaint.ping(); // repaint the face only (no full-tree rebuild)
  }

  // ── Wire 1: local gaze + presence ───────────────────────────────────────────
  void _onGaze(GazeResult r) {
    if (r.facePresent) {
      _liveGazeX = r.gazeX;
      _liveGazeY = r.gazeY;
      _present = true;
      _presenceHold?.cancel();
      _presenceHold = null;
      if (_useLivePerception && _face.state == FaceStateKind.idle) {
        _setStateKind(FaceStateKind.attentive);
      }
    } else {
      // Hold attentive briefly before returning to idle (kills jitter).
      if (_present && _presenceHold == null) {
        final hold = _face.state == FaceStateKind.greeting
            ? const Duration(seconds: 5)
            : const Duration(seconds: 3);
        _presenceHold = Timer(hold, () {
          _present = false;
          _presenceHold = null;
          if (_face.state == FaceStateKind.attentive) {
            _setStateKind(FaceStateKind.idle);
          }
        });
      }
    }
    if (mounted && kDebugMode) setState(() {}); // refresh the perception card
  }

  // ── Wire 2: spine identity + presence ───────────────────────────────────────
  void _onFaceDetected(FaceDetectedEvent e) {
    final now = DateTime.now();
    final last = _greetedAt[e.name];
    if (last != null && now.difference(last) < _regreetWindow) return; // debounce
    _greetedAt[e.name] = now;

    _cancelVoiceCycle();
    _greetTimer?.cancel();
    setState(() {
      _greetName = e.name;
      _greetVisible = true;
      _face = _face.copyWith(state: FaceStateKind.greeting);
    });
    _greetTimer = Timer(_greetHold, () {
      if (!mounted) return;
      setState(() {
        _greetVisible = false;
        _face = _face.copyWith(
            state: _present ? FaceStateKind.attentive : FaceStateKind.idle);
      });
    });
  }

  void _onPersonDetected(bool pd) {
    // Coarse presence: promote idle → attentive (eyes centered, no box to track).
    if (pd && !_present && _face.state == FaceStateKind.idle) {
      setState(() => _face =
          _face.copyWith(state: FaceStateKind.attentive, gazeX: 0, gazeY: 0));
    }
  }

  void _setStateKind(FaceStateKind k) {
    if (!mounted) return;
    setState(() => _face = _face.copyWith(state: k));
  }

  // ── Wire 3: mock voice cycle (debug) ────────────────────────────────────────
  void _startVoiceCycle() {
    _cancelVoiceCycle();
    final id = ++_voiceCycleId;
    setState(() {
      _voiceActive = true;
      _face = _face.copyWith(state: FaceStateKind.listening);
    });
    void at(int ms, FaceStateKind k, {bool end = false}) {
      _voiceTimers.add(Timer(Duration(milliseconds: ms), () {
        if (!mounted || id != _voiceCycleId) return;
        setState(() {
          _face = _face.copyWith(state: k);
          if (end) _voiceActive = false;
        });
      }));
    }

    at(3000, FaceStateKind.thinking);
    at(5000, FaceStateKind.speaking);
    at(8000, FaceStateKind.idle, end: true);
  }

  void _cancelVoiceCycle() {
    for (final t in _voiceTimers) {
      t.cancel();
    }
    _voiceTimers.clear();
    if (_voiceActive) _voiceActive = false;
  }

  // Debug-only: cycle through every state + nudge gaze manually.
  void _debugCycle() {
    _cancelVoiceCycle();
    final next = FaceStateKind
        .values[(_face.state.index + 1) % FaceStateKind.values.length];
    final expr = switch (next) {
      FaceStateKind.greeting => 1,
      FaceStateKind.thinking => 2,
      FaceStateKind.attentive => 3,
      _ => 0,
    };
    setState(() => _face = _face.copyWith(state: next, expression: expr));
  }

  void _openDashboard() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DashboardScreen()));
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final battery = ref.watch(batteryProvider);
    final sdk = ref.watch(streamProvider.select((s) => s.sdkStatus));

    ref.listen(streamProvider.select((s) => s.isStreaming), (prev, curr) {
      if (curr == true) _startControlServers();
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openDashboard,
        child: Stack(children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: FacePainter(_rig.live, repaint: _repaint)),
            ),
          ),
          // Greeting overlay — "Hi, <name>!" below the mouth.
          if (_greetName != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).size.height * 0.18,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _greetVisible ? 1 : 0,
                  duration: Duration(milliseconds: _greetVisible ? 300 : 500),
                  child: Center(
                    child: Text('Hi, $_greetName!',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          // Status chip, top-right.
          Positioned(
            top: 12,
            right: 16,
            child: Opacity(
              opacity: 0.65,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SdkBadge(status: sdk),
                const SizedBox(width: 10),
                BatteryIndicator(state: battery),
              ]),
            ),
          ),
          // Voice-cycle progress line (top).
          if (_voiceActive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_voiceCycleId),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(seconds: 8),
                builder: (_, v, __) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v.clamp(0.0, 1.0),
                  child: Container(height: 3, color: const Color(0xFFFF6B35)),
                ),
              ),
            ),
          const Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: Center(
              child: Text('tap to open dashboard',
                  style: TextStyle(color: Colors.white24, fontSize: 12)),
            ),
          ),
          if (kDebugMode) _debugPanel(),
        ]),
      ),
    );
  }

  Widget _debugPanel() {
    return Positioned(
      bottom: 12,
      left: 12,
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white54, fontSize: 11),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('state: ${_face.state.name}',
                style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('present: $_present  gaze ${_gaze.last.gazeX.toStringAsFixed(2)},'
                ' ${_gaze.last.gazeY.toStringAsFixed(2)}'),
            Text('spine: ${_spine.isConnected ? "connected" : "…"}'),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _chip('next state', _debugCycle),
              const SizedBox(width: 6),
              _chip('voice demo', _startVoiceCycle),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('live perception '),
              Switch(
                value: _useLivePerception,
                activeThumbColor: const Color(0xFFFF6B35),
                onChanged: (v) => setState(() => _useLivePerception = v),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A3A)),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      );
}

/// Lightweight per-frame repaint signal — wired to FacePainter's `repaint:` so
/// only the painter repaints each tick (no full widget rebuild).
class _FaceRepaint extends ChangeNotifier {
  void ping() => notifyListeners();
}
