import 'dart:math';

import 'package:flutter/material.dart';

/// Analog joystick, ported from the web admin's Control Room so the robot's own
/// Quick-Controls chassis pad matches it. Reports normalized (x, y) in -1..1 and
/// a magnitude; springs back to centre on release. Pure UI — the caller maps
/// (x, y, mag) to a drive direction (see AmbientFaceScreen._onDriveJoystick).
class Joystick extends StatefulWidget {
  final double size;
  final Color knobColor;
  final void Function(double x, double y, double mag) onChange;
  final VoidCallback? onEnd;
  final bool disabled;

  const Joystick({
    super.key,
    this.size = 180,
    required this.knobColor,
    required this.onChange,
    this.onEnd,
    this.disabled = false,
  });

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick>
    with SingleTickerProviderStateMixin {
  double _x = 0, _y = 0;
  bool _isDragging = false;
  late AnimationController _spring;

  double get _knobRadius => widget.size * 0.22;

  @override
  void initState() {
    super.initState();
    _spring =
        AnimationController(duration: const Duration(milliseconds: 260), vsync: this)
          ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _update(Offset globalPos, RenderBox box) {
    final local = box.globalToLocal(globalPos);
    final center = Offset(box.size.width / 2, box.size.height / 2);
    final delta = local - center;
    final maxRadius = widget.size / 2 - _knobRadius;
    final distance = sqrt(delta.dx * delta.dx + delta.dy * delta.dy);

    double x, y;
    if (distance <= maxRadius) {
      x = delta.dx / maxRadius;
      y = -delta.dy / maxRadius;
    } else {
      final angle = atan2(delta.dy, delta.dx);
      x = cos(angle);
      y = -sin(angle);
    }
    setState(() {
      _x = x.clamp(-1, 1);
      _y = y.clamp(-1, 1);
    });
    widget.onChange(_x, _y, sqrt(_x * _x + _y * _y));
  }

  void _down(PointerDownEvent e) {
    if (widget.disabled) return;
    _spring.stop();
    setState(() => _isDragging = true);
    _update(e.position, context.findRenderObject() as RenderBox);
  }

  void _move(PointerMoveEvent e) {
    if (!_isDragging || widget.disabled) return;
    _update(e.position, context.findRenderObject() as RenderBox);
  }

  void _up(PointerUpEvent e) {
    if (!_isDragging) return;
    setState(() {
      _isDragging = false;
      _x = 0;
      _y = 0;
    });
    _spring.forward(from: 0);
    widget.onChange(0, 0, 0);
    widget.onEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final maxRadius = widget.size / 2 - _knobRadius;
    // Spring: when released, _x/_y are 0, so the knob is at centre; the spring
    // just fades — the throw already snapped back. Keep it simple.
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF1C1C1C), Color(0xFF121212)],
              ),
              border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
            ),
            child: CustomPaint(painter: _Crosshair()),
          ),
          Transform.translate(
            offset: Offset(_x * maxRadius, -_y * maxRadius),
            child: Container(
              width: _knobRadius * 2,
              height: _knobRadius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.disabled
                    ? const Color(0xFF3A3A3A)
                    : widget.knobColor,
                boxShadow: widget.disabled
                    ? null
                    : [
                        BoxShadow(
                          color: widget.knobColor.withValues(alpha: 0.6),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
              ),
              child: Icon(Icons.control_camera_rounded,
                  size: _knobRadius, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _Crosshair extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..strokeWidth = 1;
    final r = size.width * 0.18;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
