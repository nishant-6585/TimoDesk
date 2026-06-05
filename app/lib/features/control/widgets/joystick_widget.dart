import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../core/constants.dart';

typedef JoystickCallback = void Function(double x, double y);

class JoystickWidget extends StatefulWidget {
  final JoystickCallback onMove;
  final VoidCallback? onEnd;
  final bool disabled;
  final String? label;

  const JoystickWidget({
    Key? key,
    required this.onMove,
    this.onEnd,
    this.disabled = false,
    this.label,
  }) : super(key: key);

  @override
  State<JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> {
  double _offsetX = 0;
  double _offsetY = 0;
  Timer? _throttleTimer;

  void _handlePanUpdate(DragUpdateDetails details) {
    if (widget.disabled) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final localPos = details.localPosition;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Calculate raw offset from center
    double rawX = localPos.dx - centerX;
    double rawY = localPos.dy - centerY;

    // Clamp to joystick radius
    final distance = (rawX * rawX + rawY * rawY).toDouble().sqrt();
    if (distance > joystickRadius) {
      final ratio = joystickRadius / distance;
      rawX *= ratio;
      rawY *= ratio;
    }

    setState(() {
      _offsetX = rawX;
      _offsetY = rawY;
    });

    // Throttle: send intent max once per 50ms
    _throttleTimer?.cancel();
    _throttleTimer = Timer(joystickThrottleMs, () {
      // Map offset to 0-100 range for spine
      final x = 50 + (_offsetX / joystickRadius) * 50;
      final y = 50 - (_offsetY / joystickRadius) * 50;
      widget.onMove(x.clamp(0, 100), y.clamp(0, 100));
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (widget.disabled) return;

    _throttleTimer?.cancel();
    setState(() {
      _offsetX = 0;
      _offsetY = 0;
    });
    widget.onEnd?.call();
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              widget.label!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: widget.disabled ? TimoColors.textSecondary : TimoColors.textPrimary,
              ),
            ),
          ),
        GestureDetector(
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          child: Opacity(
            opacity: widget.disabled ? 0.5 : 1,
            child: Container(
              width: joystickRadius * 2 + 10,
              height: joystickRadius * 2 + 10,
              decoration: BoxDecoration(
                border: Border.all(
                  color: widget.disabled ? TimoColors.textSecondary : TimoColors.primary,
                  width: 2,
                ),
                shape: BoxShape.circle,
                color: TimoColors.surface.withOpacity(0.5),
              ),
              child: Center(
                child: Transform.translate(
                  offset: Offset(_offsetX, _offsetY),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: widget.disabled ? TimoColors.textSecondary : TimoColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: TimoColors.primary.withOpacity(0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
