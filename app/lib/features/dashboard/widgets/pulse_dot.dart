import 'package:flutter/material.dart';

class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool pulse;

  const PulseDot({
    Key? key,
    required this.color,
    this.size = 10,
    this.pulse = true,
  }) : super(key: key);

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    if (widget.pulse) {
      _controller = AnimationController(
        duration: const Duration(milliseconds: 1800),
        vsync: this,
      )..repeat();

      _scaleAnimation = Tween<double>(begin: 1.0, end: 1.8).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      );

      _opacityAnimation = Tween<double>(begin: 0.55, end: 0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      );
    }
  }

  @override
  void dispose() {
    if (widget.pulse) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pulse) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        ScaleTransition(
          scale: _scaleAnimation,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
            ),
          ),
        ),
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color,
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
