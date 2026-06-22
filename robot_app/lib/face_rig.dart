import 'dart:math';

import 'face_painter.dart' show FaceState, FaceStateKind;

/// face_rig.dart — the animation layer for the Beam/OLED face (#82).
///
/// Converts the public [FaceState] contract (state · gazeX/Y · blink · mouthOpen ·
/// expression — locked in #89 §6) into a richly-smoothed [LiveState] that the
/// painter renders. All the per-state pose values (eyelids, brows, eyeArc, glow,
/// dim, ring, dots, breathing, lip-sync) are DERIVED here — they are NOT public
/// fields, so the contract the rest of the app drives stays unchanged.
///
/// Ported 1:1 from robot_app/docs/mikee_face_prototype.html (`live`, `poseFor`,
/// `exprMod`, `update`). Eases are frame-rate independent: v += (target−v)·(1−e^(−dt·k)).

/// Smoothed render values — mirrors the prototype's `live` object exactly.
class LiveState {
  double t = 0; // elapsed seconds (ring/dots/scanline + breathing phase)
  double openL = 1, openR = 1; // eyelid openness 0..1 (×blink)
  double browY = 0; // vertical brow offset, in 0.01·shortestSide units
  double browTilt = 0; // inner-up(+) / furrow(−)
  double mouthCurve = 0.25; // −1 frown .. 1 smile
  double mouthOpen = 0; // 0..1
  double eyeArc = 0; // 0 normal .. 1 happy ^_^
  double eyeScale = 1;
  double glow = 0.35; // bloom multiplier
  double dim = 1; // brightness (1 normal .. 0.5 sleepy)
  double squint = 0;
  double bounce = 0; // vertical bob, in S-multiples (painter ×S)
  double gx = 0, gy = 0; // resolved gaze −1..1
  double dots = 0; // thinking "…" visibility
  double ring = 0; // listening ring visibility
  double headTilt = 0;
  double breath = 1; // breathing rate multiplier
  double asym = 0; // curious asymmetry
}

/// Target pose for a state (the values we ease toward). Defaults = the prototype
/// `base` object.
class _Pose {
  final double openL, openR, browY, browTilt, mouthCurve, eyeArc, eyeScale, glow,
      dim, squint, gx, gy, dots, ring, headTilt, breath;
  const _Pose({
    this.openL = 1,
    this.openR = 1,
    this.browY = 0,
    this.browTilt = 0,
    this.mouthCurve = 0.25,
    this.eyeArc = 0,
    this.eyeScale = 1,
    this.glow = 0.35,
    this.dim = 1,
    this.squint = 0,
    this.gx = 0,
    this.gy = 0,
    this.dots = 0,
    this.ring = 0,
    this.headTilt = 0,
    this.breath = 1,
  });
}

/// Additive expression modifier (on top of the state pose). Defaults = no change.
class _ExprMod {
  final double mouthCurve, eyeArc, browY, browTilt, headTilt, asym, eyeScale,
      mouthOpenAdd, squint;
  const _ExprMod({
    this.mouthCurve = 0,
    this.eyeArc = 0,
    this.browY = 0,
    this.browTilt = 0,
    this.headTilt = 0,
    this.asym = 0,
    this.eyeScale = 0,
    this.mouthOpenAdd = 0,
    this.squint = 0,
  });
}

class FaceRig {
  final LiveState live = LiveState();
  final Random _rng = Random();

  // Elapsed seconds — canonical copy lives in [live.t] so the painter (which only
  // sees LiveState) can read the animation phase.
  double get t => live.t;

  // Blink scheduler.
  double _nextBlink = 1.5;
  double _blinkT = -1;

  // Idle gaze wander.
  double _wanderX = 0, _wanderY = 0, _nextWander = 0;

  static _Pose _poseFor(FaceStateKind s) {
    switch (s) {
      case FaceStateKind.attentive:
        return const _Pose(
            eyeScale: 1.14, browY: -7, browTilt: 0.12, mouthCurve: 0.12, glow: 0.5);
      case FaceStateKind.greeting:
        return const _Pose(
            eyeArc: 1, mouthCurve: 0.95, browY: -4, glow: 0.75, eyeScale: 1.04);
      case FaceStateKind.listening:
        return const _Pose(
            glow: 0.65, ring: 1, squint: 0.12, mouthCurve: 0.2, eyeScale: 1.05);
      case FaceStateKind.thinking:
        return const _Pose(
            gx: -0.55,
            gy: -0.6,
            browTilt: -0.5,
            browY: -2,
            mouthCurve: -0.05,
            dots: 1,
            eyeScale: 0.96,
            headTilt: 0.06);
      case FaceStateKind.speaking:
        return const _Pose(browY: -3, mouthCurve: 0.3, glow: 0.5);
      case FaceStateKind.sleepy:
        return const _Pose(
            openL: 0.30,
            openR: 0.30,
            browY: 5,
            mouthCurve: -0.04,
            glow: 0.12,
            dim: 0.5,
            squint: 0.5,
            breath: 0.5);
      case FaceStateKind.idle:
        return const _Pose();
    }
  }

  // expression: 0 neutral · 1 happy · 2 curious · 3 surprised
  static _ExprMod _exprMod(int e) {
    switch (e) {
      case 1:
        // Happy = a clean smiling SQUINT (not a partial ^_^ arc, which would
        // ghost over the open capsule). The full arc is greeting-only (eyeArc 1).
        return const _ExprMod(mouthCurve: 0.55, squint: 0.35, browY: -2);
      case 2:
        return const _ExprMod(
            headTilt: 0.12, browTilt: 0.3, browY: -3, mouthCurve: 0.1, asym: 1);
      case 3:
        return const _ExprMod(
            eyeScale: 0.2, browY: -9, mouthOpenAdd: 0.55, eyeArc: -1, mouthCurve: -0.15);
      default:
        return const _ExprMod();
    }
  }

  double _lerp(double a, double b, double k) => a + (b - a) * k;
  double _ease(double cur, double tgt, double dt, double speed) =>
      cur + (tgt - cur) * (1 - exp(-dt * speed));

  /// Advance one frame. [p] is the public contract; [talkingOverride] forces
  /// lip-sync (the studio "Talking" toggle); [followGx]/[followGy], when given,
  /// pin gaze to an external target (live perception / follow-touch) instead of
  /// the state pose + wander.
  void tick(
    FaceState p,
    double dt, {
    bool talkingOverride = false,
    double? followGx,
    double? followGy,
  }) {
    dt = dt.clamp(0.0, 0.05);
    live.t += dt;
    final pose = _poseFor(p.state);
    final mod = _exprMod(p.expression);

    // Blink scheduler — natural blink everywhere except sleepy.
    _blinkT -= dt;
    if (p.state != FaceStateKind.sleepy) {
      if (_blinkT < -0.25) {
        _nextBlink -= dt;
        if (_nextBlink <= 0) {
          _blinkT = 0.18;
          _nextBlink = 2.4 + _rng.nextDouble() * 3.6;
        }
      }
    }
    double autoBlink = 0;
    if (_blinkT >= 0) {
      final pp = 1 - (_blinkT / 0.18); // 0→1 over the blink
      autoBlink = sin(min(pp, 1.0) * pi); // up then down
    }

    // Idle gaze wander; decays to 0 when leaving idle.
    if (p.state == FaceStateKind.idle) {
      _nextWander -= dt;
      if (_nextWander <= 0) {
        _wanderX = (_rng.nextDouble() * 2 - 1) * 0.4;
        _wanderY = (_rng.nextDouble() * 2 - 1) * 0.28;
        _nextWander = 1.4 + _rng.nextDouble() * 2.6;
      }
    } else {
      _wanderX = _lerp(_wanderX, 0, 0.05);
      _wanderY = _lerp(_wanderY, 0, 0.05);
    }

    // Resolve gaze target.
    double gxT, gyT;
    if (followGx != null && followGy != null) {
      gxT = followGx.clamp(-1.0, 1.0);
      gyT = followGy.clamp(-1.0, 1.0);
    } else {
      gxT = (p.gazeX + pose.gx + _wanderX).clamp(-1.2, 1.2);
      gyT = (p.gazeY + pose.gy + _wanderY).clamp(-1.2, 1.2);
    }

    // Mouth target.
    final talking = talkingOverride || p.state == FaceStateKind.speaking;
    double mouthT;
    if (talking) {
      mouthT = 0.5 + 0.32 * sin(t * 15) + 0.16 * sin(t * 8.3 + 1);
      mouthT = (mouthT.abs() * 0.7).clamp(0.04, 1.0);
    } else {
      // Only the surprised expression opens the mouth at rest (mouthOpenAdd).
      mouthT = max(p.mouthOpen, mod.mouthOpenAdd);
    }

    // Eyelids (state openness × (1 − blink)).
    final blinkAmt = max(autoBlink, p.blink);
    final openLT = pose.openL * (1 - blinkAmt);
    final openRT = pose.openR * (1 - blinkAmt);

    // Targets.
    final tBrowY = pose.browY + mod.browY;
    final tBrowTilt = pose.browTilt + mod.browTilt;
    final tMouthCurve = (pose.mouthCurve + mod.mouthCurve).clamp(-1.0, 1.0);
    final tEyeArc = (pose.eyeArc + mod.eyeArc).clamp(0.0, 1.0);
    final tEyeScale = pose.eyeScale + mod.eyeScale;
    final tHeadTilt = pose.headTilt + mod.headTilt;
    final tBreath = pose.breath;
    final tAsym = mod.asym;
    final tSquint = (pose.squint + mod.squint).clamp(0.0, 1.0);

    // Breathing bob + greeting bounce (S-multiples; painter ×S).
    final breathPhase = sin(t * 1.1 * tBreath);
    final greetBounce =
        p.state == FaceStateKind.greeting ? max(0.0, sin(t * 5)) * 10 : 0.0;
    live.bounce = breathPhase * 5 - greetBounce;

    // Ease everything (k=20 eyelids, k=22 mouthOpen, k=9 the rest).
    live.openL = _ease(live.openL, openLT, dt, 20);
    live.openR = _ease(live.openR, openRT, dt, 20);
    live.mouthOpen = _ease(live.mouthOpen, mouthT, dt, 22);
    live.browY = _ease(live.browY, tBrowY, dt, 9);
    live.browTilt = _ease(live.browTilt, tBrowTilt, dt, 9);
    live.mouthCurve = _ease(live.mouthCurve, tMouthCurve, dt, 9);
    live.eyeArc = _ease(live.eyeArc, tEyeArc, dt, 9);
    live.eyeScale = _ease(live.eyeScale, tEyeScale, dt, 9);
    live.glow = _ease(live.glow, pose.glow, dt, 9);
    live.dim = _ease(live.dim, pose.dim, dt, 9);
    live.squint = _ease(live.squint, tSquint, dt, 9);
    live.gx = _ease(live.gx, gxT, dt, 9);
    live.gy = _ease(live.gy, gyT, dt, 9);
    live.dots = _ease(live.dots, pose.dots, dt, 9);
    live.ring = _ease(live.ring, pose.ring, dt, 9);
    live.headTilt = _ease(live.headTilt, tHeadTilt, dt, 9);
    live.breath = _ease(live.breath, tBreath, dt, 9);
    live.asym = _ease(live.asym, tAsym, dt, 9);
  }
}
