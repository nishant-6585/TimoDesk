import 'package:flutter/material.dart';

/// Full-screen overlay that shows a custom-drawn waving palm + greeting text
/// when Mikee detects a visitor. [visible] controls fade in/out; the caller
/// sets it to false after the hold timer expires.
///
/// Uses a [CustomPainter] palm so it looks sharp on every Android version
/// (avoids the monochrome Noto glyph that Android 7.1.2 would render for 👋).
/// Colors match the FacePainter palette: cream #FFE3CE body + orange #FF6B35 glow.
class WavingHandOverlay extends StatefulWidget {
  final bool visible;
  final String message;

  const WavingHandOverlay({
    super.key,
    required this.visible,
    this.message = 'Hello!',
  });

  @override
  State<WavingHandOverlay> createState() => _WavingHandOverlayState();
}

class _WavingHandOverlayState extends State<WavingHandOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _angle;

  @override
  void initState() {
    super.initState();
    // 420 ms per half-wave → ~2.4 waves/sec (natural wrist tempo).
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..repeat(reverse: true);
    // Pivot at the wrist (Alignment.bottomCenter): −25° inward → +20° outward.
    _angle = Tween<double>(begin: -0.44, end: 0.35).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handSize = MediaQuery.of(context).size.shortestSide * 0.28;
    return AnimatedOpacity(
      opacity: widget.visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 320),
      child: IgnorePointer(
        child: Align(
          // Lower-center so the face's eyes remain visible above.
          alignment: const Alignment(0.0, 0.55),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Greeting text pill (orange-bordered, semi-transparent dark).
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.60),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFFFF6B35).withValues(alpha: 0.65),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Waving palm — pivots at wrist (Alignment.bottomCenter).
              AnimatedBuilder(
                animation: _angle,
                builder: (_, __) => Transform.rotate(
                  angle: _angle.value,
                  alignment: Alignment.bottomCenter,
                  child: CustomPaint(
                    size: Size(handSize, handSize * 1.15),
                    painter: const _PalmPainter(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws an open, forward-facing palm in the project's accent palette.
///
/// Geometry is in a 100 × 115 unit space; everything is scaled by
/// [size.width / 100] so the hand scales cleanly at any render size.
/// Two-pass render: blurred orange glow → sharp cream fill (same technique
/// as [FacePainter._withGlow]).
class _PalmPainter extends CustomPainter {
  const _PalmPainter();

  // Match FacePainter color tokens exactly.
  static const _handColor = Color(0xFFFFE3CE); // warm cream (= _eye)
  static const _glowColor = Color(0xFFFF6B35); // accent orange (= _accent)

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;

    final glow = Paint()
      ..color = _glowColor.withValues(alpha: 0.38)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * s);
    final fill = Paint()..color = _handColor;

    // Draw the whole hand shape with the given paint (called twice: glow, fill).
    void drawHand(Paint p) {
      void rr(double x, double y, double w, double h, double r) =>
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x * s, y * s, w * s, h * s),
              Radius.circular(r * s),
            ),
            p,
          );

      // Four upright fingers (pinky → index, left to right).
      rr(10, 22, 13, 52, 6.5); // pinky   (shortest)
      rr(26, 12, 15, 62, 6.5); // ring
      rr(44,  5, 15, 69, 6.5); // middle  (tallest)
      rr(62, 10, 15, 64, 6.5); // index

      // Thumb — angled ~31° outward from the wrist.
      canvas.save();
      canvas.translate(88.5 * s, 63 * s);
      canvas.rotate(0.55); // radians ≈ 31°
      rr(-6.5, -14, 13, 34, 6.5);
      canvas.restore();

      // Palm base connecting all fingers.
      rr(8, 68, 82, 36, 14);
    }

    drawHand(glow);
    drawHand(fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
