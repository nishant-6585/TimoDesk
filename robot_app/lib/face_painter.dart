import 'package:flutter/material.dart';

/// Avatar states — mirrors the Rive `state` input (#82 / design §6).
/// 0 idle · 1 attentive · 2 greeting · 3 listening · 4 thinking · 5 speaking · 6 sleepy
enum FaceStateKind { idle, attentive, greeting, listening, thinking, speaking, sleepy }

/// The full face input contract (design §6). Code owns these values; the painter
/// (and later the Rive asset) only renders them. Swapping in `.riv` later means
/// feeding the same fields into Rive inputs — no state-wiring change.
class FaceState {
  final FaceStateKind state;
  final double gazeX; // -1..1  (left..right)
  final double gazeY; // -1..1  (up..down)
  final double blink; // 0 open .. 1 closed
  final double mouthOpen; // 0..1 (amplitude lip-sync, P4)
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

/// PLACEHOLDER face — a simple, GPU-light CustomPainter (eyes + brows + mouth)
/// wired to [FaceState]. Designed to be swapped for the polished Rive `.riv`
/// asset later without touching the state wiring. Kept to basic shapes for
/// Android 7.1.2.
class FacePainter extends CustomPainter {
  final FaceState face;
  const FacePainter(this.face);

  static const _orange = Color(0xFFFF6B35);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final unit = size.shortestSide;
    final eyeR = unit * 0.10;
    final eyeDx = unit * 0.20;
    final eyeY = cy - unit * 0.06;

    final happy = face.expression == 1 || face.state == FaceStateKind.greeting;
    final surprised = face.expression == 3 || face.state == FaceStateKind.attentive;
    final dim = face.state == FaceStateKind.sleepy;

    final scleraPaint = Paint()..color = dim ? const Color(0xFF2A2A2A) : const Color(0xFFEDEDED);
    final pupilPaint = Paint()..color = const Color(0xFF121212);

    // Eye openness: 1 - blink, with state nudges (surprised wider, sleepy half).
    double open = (1 - face.blink).clamp(0.0, 1.0);
    if (surprised) open = (open * 1.15).clamp(0.0, 1.0);
    if (dim) open = open * 0.5;

    for (final sign in [-1.0, 1.0]) {
      final ex = cx + sign * eyeDx;
      // Eye (rounded rect, height scaled by openness = blink/lid).
      final eyeRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(ex, eyeY), width: eyeR * 2.0, height: eyeR * 2.0 * open),
        Radius.circular(eyeR),
      );
      canvas.drawRRect(eyeRect, scleraPaint);
      // Pupil — offset by gaze.
      if (open > 0.15) {
        final px = ex + face.gazeX * eyeR * 0.7;
        final py = eyeY + face.gazeY * eyeR * 0.6;
        canvas.drawCircle(Offset(px, py), eyeR * 0.45 * open, pupilPaint);
      }
      // Brow — angle/lift by expression.
      final browPaint = Paint()
        ..color = const Color(0xFF9A9A9A)
        ..strokeWidth = unit * 0.018
        ..strokeCap = StrokeCap.round;
      final browY = eyeY - eyeR * (surprised ? 1.9 : 1.4);
      final tilt = happy ? -eyeR * 0.18 : (face.expression == 2 ? eyeR * 0.25 * sign : 0.0);
      canvas.drawLine(
        Offset(ex - eyeR * 0.8, browY + tilt),
        Offset(ex + eyeR * 0.8, browY - tilt),
        browPaint,
      );
    }

    // Mouth — smile when happy, with openness (speaking/lip-sync).
    final mouthY = cy + unit * 0.16;
    final mouthW = unit * 0.26;
    final mouthPaint = Paint()
      ..color = _orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.022
      ..strokeCap = StrokeCap.round;
    final openH = face.mouthOpen.clamp(0.0, 1.0) * unit * 0.10;
    if (openH > unit * 0.012) {
      // Open mouth (speaking) — filled oval.
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, mouthY), width: mouthW * 0.7, height: openH * 2),
        Paint()..color = _orange,
      );
    } else {
      // Closed mouth — curve; happy = upward smile, else gentle line.
      final curve = happy ? -unit * 0.06 : (dim ? unit * 0.01 : unit * 0.015);
      final path = Path()
        ..moveTo(cx - mouthW / 2, mouthY)
        ..quadraticBezierTo(cx, mouthY + curve * (happy ? 1 : -1) + (happy ? 0 : 0), cx + mouthW / 2, mouthY);
      if (happy) {
        path.reset();
        path.moveTo(cx - mouthW / 2, mouthY);
        path.quadraticBezierTo(cx, mouthY + unit * 0.08, cx + mouthW / 2, mouthY);
      }
      canvas.drawPath(path, mouthPaint);
    }
  }

  @override
  bool shouldRepaint(FacePainter old) =>
      old.face.gazeX != face.gazeX ||
      old.face.gazeY != face.gazeY ||
      old.face.blink != face.blink ||
      old.face.mouthOpen != face.mouthOpen ||
      old.face.state != face.state ||
      old.face.expression != face.expression;
}
