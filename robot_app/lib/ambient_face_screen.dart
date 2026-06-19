import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'app_widgets.dart';
import 'face_painter.dart';
import 'dashboard_screen.dart';

/// The robot's front-of-house home: an ambient animated face (placeholder
/// CustomPainter, swappable for Rive later). Idle life = randomized blink +
/// gentle gaze drift (lerped, never snapped). Tap anywhere → Dashboard.
/// P1 = mock state only (debug toggle cycles all states); real perception is P2.
class AmbientFaceScreen extends ConsumerStatefulWidget {
  const AmbientFaceScreen({super.key});

  @override
  ConsumerState<AmbientFaceScreen> createState() => _AmbientFaceScreenState();
}

class _AmbientFaceScreenState extends ConsumerState<AmbientFaceScreen> {
  final _rng = Random();
  FaceState _face = const FaceState();

  // Gaze lerp targets + blink animation state.
  double _gazeTX = 0, _gazeTY = 0;
  bool _blinkClosing = false;

  Timer? _ticker; // ~20fps animation loop (lerp gaze + blink)
  Timer? _blinkTimer; // schedules the next blink (2–6s)
  Timer? _driftTimer; // schedules the next gaze drift (3–6s)

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
    _scheduleBlink();
    _scheduleDrift();
    // Preserve old behavior: bring up the control WS servers (:8081-3) if the
    // camera is already streaming when we mount, so the admin joystick works
    // without anyone opening Manual Control on the robot.
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
    _ticker?.cancel();
    _blinkTimer?.cancel();
    _driftTimer?.cancel();
    super.dispose();
  }

  void _scheduleBlink() {
    _blinkTimer = Timer(Duration(milliseconds: 2000 + _rng.nextInt(4000)), () {
      _blinkClosing = true; // ticker animates the lid down then up
      _scheduleBlink();
    });
  }

  void _scheduleDrift() {
    _driftTimer = Timer(Duration(milliseconds: 3000 + _rng.nextInt(3000)), () {
      // Small random target so the eyes wander gently.
      _gazeTX = (_rng.nextDouble() - 0.5) * 1.2;
      _gazeTY = (_rng.nextDouble() - 0.5) * 0.8;
      _scheduleDrift();
    });
  }

  void _tick() {
    // Lerp gaze toward target (smooth, never snap).
    final gx = _face.gazeX + (_gazeTX - _face.gazeX) * 0.12;
    final gy = _face.gazeY + (_gazeTY - _face.gazeY) * 0.12;

    // Blink animation: close fast, then open.
    double blink = _face.blink;
    if (_blinkClosing) {
      blink += 0.4;
      if (blink >= 1) { blink = 1; _blinkClosing = false; }
    } else if (blink > 0) {
      blink = (blink - 0.34).clamp(0.0, 1.0);
    }

    setState(() => _face = _face.copyWith(gazeX: gx, gazeY: gy, blink: blink));
  }

  // Debug-only: cycle through every state + nudge gaze, so all states demo
  // without hardware (P1 acceptance).
  void _debugCycle() {
    final next = FaceStateKind.values[(_face.state.index + 1) % FaceStateKind.values.length];
    final expr = switch (next) {
      FaceStateKind.greeting => 1,
      FaceStateKind.thinking => 2,
      FaceStateKind.attentive => 3,
      _ => 0,
    };
    final mouth = (next == FaceStateKind.speaking) ? 0.6 : 0.0;
    setState(() => _face = _face.copyWith(state: next, expression: expr, mouthOpen: mouth));
    _gazeTX = (_rng.nextDouble() - 0.5) * 1.6;
    _gazeTY = (_rng.nextDouble() - 0.5) * 1.0;
  }

  void _openDashboard() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DashboardScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final battery = ref.watch(batteryProvider);
    final sdk = ref.watch(streamProvider.select((s) => s.sdkStatus));

    // Control servers come up the moment the camera starts streaming.
    ref.listen(streamProvider.select((s) => s.isStreaming), (prev, curr) {
      if (curr == true) _startControlServers();
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openDashboard,
        child: Stack(children: [
          // The face fills the screen.
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: FacePainter(_face)),
            ),
          ),
          // Unobtrusive status chip, top-right.
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
          // Tap hint, bottom.
          const Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: Center(
              child: Text('tap to open dashboard',
                  style: TextStyle(color: Colors.white24, fontSize: 12)),
            ),
          ),
          // Debug-only state cycler.
          if (kDebugMode)
            Positioned(
              bottom: 14,
              right: 14,
              child: FloatingActionButton.small(
                backgroundColor: const Color(0xFF2A2A2A),
                onPressed: _debugCycle,
                child: const Icon(Icons.bug_report, color: kOrange),
              ),
            ),
          if (kDebugMode)
            Positioned(
              bottom: 20,
              left: 16,
              child: Text('state: ${_face.state.name}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ),
        ]),
      ),
    );
  }
}
