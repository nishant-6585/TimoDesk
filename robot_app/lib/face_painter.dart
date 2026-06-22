import 'dart:math';

import 'package:flutter/material.dart';

import 'face_rig.dart' show LiveState;

/// Avatar states — the locked #89 §6 / #82 Rive `state` contract.
/// 0 idle · 1 attentive · 2 greeting · 3 listening · 4 thinking · 5 speaking · 6 sleepy
enum FaceStateKind { idle, attentive, greeting, listening, thinking, speaking, sleepy }

/// The public face input contract (design §6). Code owns these values; the painter
/// (via [LiveState] from [FaceRig]) renders them. Swapping in a Rive `.riv` later
/// means feeding the SAME fields into Rive inputs — no state-wiring change.
class FaceState {
  final FaceStateKind state;
  final double gazeX; // -1..1  (left..right)
  final double gazeY; // -1..1  (up..down)
  final double blink; // 0 open .. 1 closed
  final double mouthOpen; // 0..1 (amplitude lip-sync)
  final int expression; // 0 neutral · 1 happy · 2 curious · 3 surprised

  const FaceState({
    this.state = FaceStateKind.idle,
    this.gazeX = 0,
    this.gazeY = 0,
    this.blink = 0,
    this.mouthOpen = 0,
    this.expression = 0,
  });

  FaceState copyWith({
    FaceStateKind? state,
    double? gazeX,
    double? gazeY,
    double? blink,
    double? mouthOpen,
    int? expression,
  }) =>
      FaceState(
        state: state ?? this.state,
        gazeX: gazeX ?? this.gazeX,
        gazeY: gazeY ?? this.gazeY,
        blink: blink ?? this.blink,
        mouthOpen: mouthOpen ?? this.mouthOpen,
        expression: expression ?? this.expression,
      );
}

/// Beam / OLED face painter (#82). Renders a smoothed [LiveState] — a faithful
/// port of robot_app/docs/mikee_face_prototype.html (Beam style only), per the
/// constants in robot_app/docs/mikee_face_poses.md.
///
/// Glow is two-pass: a blurred bloom copy (accent, MaskFilter) THEN the sharp
/// shape — canvas2d's shadowBlur has no 1:1 Flutter equivalent.
class FacePainter extends CustomPainter {
  final LiveState live;
  double get t => live.t; // animation phase (ring/dots/scanline/breath)
  const FacePainter(this.live, {Listenable? repaint}) : super(repaint: repaint);

  // ── Color tokens (mikee_face_poses.md §A) ──────────────────────────────────
  static const Color _bg = Color(0xFF0F0F0F);
  static const Color _eye = Color(0xFFFFE3CE); // warm off-white
  static const Color _accent = Color(0xFFFF6B35);
  static const Color _pupil = Color(0xFF3A1604);
  static const Color _mouthOpenFill = Color(0xFF5A1E06);
  static const Color _tongue = Color(0xFFFF6B35);
  static const Color _catchlight = Color(0xFFFFFFFF);

  // ── Geometry (×S, S = shortestSide / 100) ─────────────────────────────────
  static const double _eyeGap = 26; // center→center half, ×S
  static const double _eyeYUnit = -8; // eyes above midline, ×S
  static const double _mouthYUnit = 26; // mouth below center, ×S
  static const double _eyeWUnit = 19;
  static const double _eyeHUnit = 24;
  static const double _eyeRadUnit = 7;
  static const double _irisUnit = 8.5;
  static const double _browThick = 5.5;
  static const double _browLen = 20;
  static const double _mouthWUnit = 34;
  static const double _mouthOpenMax = 26;
  static const double _mouthCurveAmt = 18;
  static const double _lipStroke = 6.5;

  // ── Glow sigma multipliers — tune these on the real robot (see HANDOFF #82).
  // Current values are conservative for Android 7.1.2. Spec-implied targets (blur/2):
  // eye ~17·S, brow ~5·S, mouth ~8·S. Raise toward those if the panel can hold it.
  static const double _kEyeGlowCoeff = 8.0; // was 4.0
  static const double _kBrowGlowCoeff = 3.0; // was 2.0
  static const double _kMouthGlowCoeff = 5.0; // was 3.0
  static const double _kDotGlowCoeff = 2.5; // was 2.0

  double _eyeGlow(double s) => (0.5 + live.glow) * _kEyeGlowCoeff * s;
  double _browGlow(double s) => (0.4 + live.glow) * _kBrowGlowCoeff * s;
  double _mouthGlow(double s) => (0.4 + live.glow) * _kMouthGlowCoeff * s;
  double _dotGlow(double s) => _kDotGlowCoeff * s;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

    final s = size.shortestSide / 100.0;
    final cx = size.width / 2;
    final cy = size.height / 2 + live.bounce * s;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(live.headTilt * 0.12);

    final eyeGap = _eyeGap * s;
    final eyeY = _eyeYUnit * s;
    final mouthY = _mouthYUnit * s;

    // Listening ring (behind the face).
    if (live.ring > 0.02) {
      final pr = (44 + sin(t * 3.2) * 4) * s;
      final ringA =
          (live.ring * (0.18 + 0.12 * sin(t * 3.2))).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(0, 6 * s),
        pr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * s
          ..color = _accent.withValues(alpha: ringA),
      );
    }

    _drawBrow(canvas, -eyeGap, eyeY, s, -1);
    _drawBrow(canvas, eyeGap, eyeY, s, 1);
    _drawEye(canvas, -eyeGap, eyeY, s, -1);
    _drawEye(canvas, eyeGap, eyeY, s, 1);
    _drawMouth(canvas, 0, mouthY, s);

    if (live.dots > 0.02) {
      _drawDots(canvas, eyeGap + 16 * s, eyeY - 30 * s, s);
    }

    canvas.restore();

    // Beam scanlines (OLED texture) — full screen, after the face group.
    final scan = Paint()..color = Colors.black.withValues(alpha: 0.05);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), scan);
    }
  }

  // Two-pass glow: blurred accent bloom, then the sharp shape.
  void _withGlow(
    Canvas canvas,
    double sigma,
    double glowAlpha,
    Paint real,
    void Function(Paint) drawShape,
  ) {
    final bloom = Paint()
      ..style = real.style
      ..strokeWidth = real.strokeWidth
      ..strokeCap = real.strokeCap
      ..color = _accent.withValues(alpha: glowAlpha.clamp(0.0, 1.0))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, max(0.01, sigma));
    drawShape(bloom);
    drawShape(real);
  }

  Color _shade(Color c, double mul) => Color.fromARGB(
        255,
        (c.r * 255 * mul).round().clamp(0, 255),
        (c.g * 255 * mul).round().clamp(0, 255),
        (c.b * 255 * mul).round().clamp(0, 255),
      );

  void _drawEye(Canvas canvas, double ox, double oy, double s, int side) {
    final dim = live.dim;
    final baseW = _eyeWUnit * s * live.eyeScale;
    final baseH = _eyeHUnit * s * live.eyeScale;
    double open = side < 0 ? live.openL : live.openR;
    if (live.asym > 0.02 && side > 0) open = min(1.0, open * 1.05); // curious
    open = open.clamp(0.04, 1.3);
    final h = baseH * (1 - live.squint * 0.35) * min(open, 1.25);
    final w = baseW;
    final rad = _eyeRadUnit * s;
    final arc = live.eyeArc;
    final col = _shade(_eye, dim);
    final sigma = _eyeGlow(s);

    final eyeRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(ox, oy), width: w, height: h),
      Radius.circular(rad),
    );

    // Normal eye (alpha 1−arc).
    if (arc < 0.985) {
      final a = (1 - arc).clamp(0.0, 1.0);
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = col.withValues(alpha: a);
      _withGlow(canvas, sigma, dim * a * 0.6, fill,
          (p) => canvas.drawRRect(eyeRRect, p));

      // Iris / pupil / catchlight — clipped to the eye.
      canvas.save();
      canvas.clipRRect(eyeRRect);
      final gx = live.gx.clamp(-1.0, 1.0) * w * 0.42;
      final gy = live.gy.clamp(-1.0, 1.0) * h * 0.42;
      final ir = _irisUnit * s;
      canvas.drawCircle(Offset(ox + gx, oy + gy), ir,
          Paint()..color = _accent.withValues(alpha: dim * a));
      canvas.drawCircle(Offset(ox + gx, oy + gy), ir * 0.52,
          Paint()..color = _shade(_pupil, dim).withValues(alpha: a));
      canvas.drawCircle(
          Offset(ox + gx + ir * 0.4, oy + gy - ir * 0.5),
          ir * 0.32,
          Paint()..color = _catchlight.withValues(alpha: dim * 0.95 * a));
      canvas.drawCircle(
          Offset(ox + gx - ir * 0.35, oy + gy + ir * 0.4),
          ir * 0.16,
          Paint()..color = _catchlight.withValues(alpha: dim * 0.48 * a));
      canvas.restore();
    }

    // Happy ^_^ arc (alpha arc).
    if (arc > 0.015) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * s
        ..strokeCap = StrokeCap.round
        ..color = col.withValues(alpha: arc.clamp(0.0, 1.0));
      final aw = w * 1.15;
      final path = Path()
        ..moveTo(ox - aw / 2, oy + h * 0.18)
        ..quadraticBezierTo(ox, oy - h * 0.55, ox + aw / 2, oy + h * 0.18);
      _withGlow(canvas, sigma, dim * arc * 0.7, stroke,
          (p) => canvas.drawPath(path, p));
    }
  }

  void _drawBrow(Canvas canvas, double ox, double oy, double s, int side) {
    if (live.eyeArc > 0.6) return; // hidden when ^_^
    final dim = live.dim;
    final w = _browLen * s * live.eyeScale;
    final y = oy - 22 * s + live.browY * s;
    double tilt = live.browTilt * 0.5;
    if (live.asym > 0.02) tilt += side > 0 ? -0.25 : 0.08; // curious: raise right
    final innerY = y + (side * -tilt) * 10 * s;
    final outerY = y + (side * tilt) * 6 * s;
    final a = ((1 - live.eyeArc) * dim).clamp(0.0, 1.0);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _browThick * s
      ..strokeCap = StrokeCap.round
      ..color = _shade(_eye, dim).withValues(alpha: a);
    final innerX = ox - side * w / 2, outerX = ox + side * w / 2;
    final path = Path()
      ..moveTo(innerX, innerY)
      ..lineTo(outerX, outerY);
    _withGlow(canvas, _browGlow(s), dim * a * 0.5, stroke,
        (p) => canvas.drawPath(path, p));
  }

  void _drawMouth(Canvas canvas, double ox, double oy, double s) {
    final dim = live.dim;
    final mw = _mouthWUnit * s;
    final curve = live.mouthCurve;
    final openH = live.mouthOpen * _mouthOpenMax * s;
    final amt = _mouthCurveAmt * s;
    final cornerY = oy - curve * amt * 0.5;
    final ctrlY = oy + curve * amt;
    final col = _shade(_accent, dim);
    final sigma = _mouthGlow(s);
    final glowA = dim * 0.5;

    // Inner mouth + tongue when open.
    if (openH > 0.3 * s) {
      final inner = Path()
        ..moveTo(ox - mw / 2, cornerY - openH / 2)
        ..quadraticBezierTo(ox, ctrlY - openH / 2, ox + mw / 2, cornerY - openH / 2)
        ..lineTo(ox + mw / 2, cornerY + openH / 2)
        ..quadraticBezierTo(ox, ctrlY + openH / 2, ox - mw / 2, cornerY + openH / 2)
        ..close();
      canvas.drawPath(
          inner, Paint()..color = _mouthOpenFill.withValues(alpha: dim));
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(ox, ctrlY + openH * 0.18),
            width: mw * 0.60,
            height: openH * 0.60),
        Paint()..color = _tongue.withValues(alpha: dim * 0.55),
      );
    }

    // Upper lip — always (defines smile/frown).
    final lip = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _lipStroke * s
      ..strokeCap = StrokeCap.round
      ..color = col;
    final upper = Path()
      ..moveTo(ox - mw / 2, cornerY - openH / 2)
      ..quadraticBezierTo(ox, ctrlY - openH / 2, ox + mw / 2, cornerY - openH / 2);
    _withGlow(canvas, sigma, glowA, lip, (p) => canvas.drawPath(upper, p));

    // Lower lip — only when open.
    if (openH > 0.3 * s) {
      final lower = Path()
        ..moveTo(ox - mw / 2, cornerY + openH / 2)
        ..quadraticBezierTo(ox, ctrlY + openH / 2, ox + mw / 2, cornerY + openH / 2);
      _withGlow(canvas, sigma, glowA, lip, (p) => canvas.drawPath(lower, p));
    }
  }

  void _drawDots(Canvas canvas, double ox, double oy, double s) {
    final phase = (t * 1.6) % 3;
    for (int i = 0; i < 3; i++) {
      final a = (1 - (phase - i).abs()).clamp(0.25, 1.0) * live.dots;
      final paint = Paint()..color = _accent.withValues(alpha: a.clamp(0.0, 1.0));
      _withGlow(canvas, _dotGlow(s), a * 0.8, paint,
          (p) => canvas.drawCircle(Offset(ox + i * 11 * s, oy), 4 * s, p));
    }
  }

  @override
  bool shouldRepaint(covariant FacePainter old) => true; // driven every frame
}
