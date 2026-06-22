import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';

/// DOM id of the laptop webcam <video>. The face-api detection loop targets this
/// (`#enroll-webcam-video`), exactly like it targets the MJPEG <img> for the robot.
const String kEnrollWebcamId = 'enroll-webcam-video';

int _factoryCounter = 0;

/// Laptop/device webcam source for enrollment. getUserMedia → <video> mounted via
/// HtmlElementView so the person, the camera, and the on-screen guidance are all
/// on the same screen. Handles permission denial gracefully.
class DeviceWebcamView extends StatefulWidget {
  const DeviceWebcamView({Key? key}) : super(key: key);

  @override
  State<DeviceWebcamView> createState() => _DeviceWebcamViewState();
}

class _DeviceWebcamViewState extends State<DeviceWebcamView> {
  String _status = 'requesting'; // requesting | ready | denied
  String _error = '';
  html.MediaStream? _stream;
  String? _viewType;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _status = 'requesting';
      _error = '';
    });
    try {
      final media = html.window.navigator.mediaDevices;
      if (media == null) {
        throw Exception('Camera API not available in this browser');
      }
      final stream = await media.getUserMedia({
        'video': {'facingMode': 'user'},
        'audio': false,
      });
      _stream = stream;

      final viewType = 'enroll-webcam-${_factoryCounter++}';
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
        final video = html.VideoElement()
          ..id = kEnrollWebcamId
          ..autoplay = true
          ..muted = true
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover';
        video.setAttribute('playsinline', 'true');
        video.srcObject = stream;
        // Best-effort autoplay (some browsers require an explicit play()).
        video.play();
        return video;
      });

      if (!mounted) {
        stream.getTracks().forEach((t) => t.stop());
        return;
      }
      setState(() {
        _viewType = viewType;
        _status = 'ready';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'denied';
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _stream?.getTracks().forEach((t) => t.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_status == 'ready' && _viewType != null) {
      return HtmlElementView(viewType: _viewType!);
    }
    if (_status == 'denied') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, size: 56, color: Color(0xFF3A3A3A)),
              const SizedBox(height: 16),
              Text(
                'Camera access needed',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Allow camera permission in your browser to enroll from this device,\n'
                'or switch the source to the robot camera.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: MikeeColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}
