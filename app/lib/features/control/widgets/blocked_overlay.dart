import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';

class BlockedOverlay extends StatelessWidget {
  final bool visible;

  const BlockedOverlay({
    Key? key,
    required this.visible,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.warning_rounded,
              color: Color(0xFFF59E0B),
              size: 64,
            ),
            const SizedBox(height: 24),
            Text(
              'PATH BLOCKED',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Robot halted by obstacle',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: TimoColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Obstacle detected ahead. Robot will navigate around it.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: TimoColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
