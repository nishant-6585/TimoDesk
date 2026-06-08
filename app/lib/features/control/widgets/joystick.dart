import 'package:flutter/material.dart';
import 'dart:math';

class Joystick extends StatefulWidget {
  final double size;
  final Color knobColor;
  final Function(double x, double y, double mag) onChange;
  final VoidCallback? onEnd;
  final bool disabled;

  const Joystick({
    Key? key,
    this.size = 200,
    required this.knobColor,
    required this.onChange,
    this.onEnd,
    this.disabled = false,
  }) : super(key: key);

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> with SingleTickerProviderStateMixin {
  double _x = 0, _y = 0;
  bool _isDragging = false;
  late AnimationController _springController;
  late Animation<Offset> _springAnimation;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(duration: const Duration(milliseconds: 280), vsync: this);
    _springAnimation = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _updatePosition(Offset globalPosition, RenderBox box) {
    final localPosition = box.globalToLocal(globalPosition);
    final center = Offset(box.size.width / 2, box.size.height / 2);
    final delta = localPosition - center;
    
    final maxRadius = widget.size / 2 - 40;
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

    final mag = sqrt(_x * _x + _y * _y);
    widget.onChange(_x, _y, mag);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.disabled) return;
    setState(() => _isDragging = true);
    final box = context.findRenderObject() as RenderBox;
    _updatePosition(event.position, box);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isDragging || widget.disabled) return;
    final box = context.findRenderObject() as RenderBox;
    _updatePosition(event.position, box);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_isDragging || widget.disabled) return;
    setState(() => _isDragging = false);
    widget.onEnd?.call();

    _springAnimation = Tween<Offset>(
      begin: Offset(_x * 40, -_y * 40),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _springController, curve: Curves.easeOutCubic));

    _springController.forward(from: 0.0);

    setState(() {
      _x = 0;
      _y = 0;
    });
    widget.onChange(0, 0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final baseRadius = widget.size / 2;
    final knobRadius = 40.0;
    final maxRadius = baseRadius - knobRadius;

    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Base circle with gradient
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
            child: CustomPaint(
              painter: _CrosshairPainter(),
            ),
          ),
          // Dashed deadzone ring
          Container(
            width: widget.size * 0.56,
            height: widget.size * 0.56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF2A2A2A),
                width: 1,
                style: BorderStyle.solid,
              ),
            ),
            child: CustomPaint(
              painter: _DeadzonePainter(),
            ),
          ),
          // Animated knob
          AnimatedBuilder(
            animation: _springAnimation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(_x * maxRadius + _springAnimation.value.dx, -_y * maxRadius + _springAnimation.value.dy),
                child: child,
              );
            },
            child: Container(
              width: knobRadius * 2,
              height: knobRadius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.knobColor,
                boxShadow: [
                  BoxShadow(
                    color: widget.knobColor.withOpacity(0.6),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(Icons.add, size: 28, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..strokeWidth = 1;

    // Horizontal line
    canvas.drawLine(
      Offset(center.dx - 30, center.dy),
      Offset(center.dx + 30, center.dy),
      paint,
    );

    // Vertical line
    canvas.drawLine(
      Offset(center.dx, center.dy - 30),
      Offset(center.dx, center.dy + 30),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DeadzonePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = const Color(0xFF2A2A2A).withOpacity(0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const dashWidth = 4.0;
    const dashSpace = 4.0;
    final circumference = 2 * pi * radius;
    final dashCount = (circumference / (dashWidth + dashSpace)).toInt();

    for (int i = 0; i < dashCount; i++) {
      final angle1 = (i * (dashWidth + dashSpace) / radius);
      final angle2 = ((i * (dashWidth + dashSpace) + dashWidth) / radius);

      canvas.drawArc(
        Rect.fromCenter(center: center, width: radius * 2, height: radius * 2),
        angle1,
        angle2 - angle1,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
