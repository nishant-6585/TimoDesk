import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';

/// DOM id of the webcam <video> on web. Defined here too so the public API of
/// the seam is identical on native (callers import it unconditionally).
const String kEnrollWebcamId = 'enroll-webcam-video';

/// Native fallback for the web-only getUserMedia webcam. Webcam + browser
/// face-api enrollment only exist on the web build; on a device, enroll from the
/// robot chest screen (or the web admin). Same constructor as the web version.
class DeviceWebcamView extends StatelessWidget {
  const DeviceWebcamView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.computer, size: 56, color: Color(0xFF3A3A3A)),
            const SizedBox(height: 16),
            Text(
              'Webcam enrollment is web-only',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Use the web app to enroll from a laptop webcam,\n'
              'or use the robot chest screen to enroll here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: TimoColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
