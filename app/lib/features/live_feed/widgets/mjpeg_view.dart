import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Robot camera viewer — polls the `/snapshot` endpoint (~10 fps) instead of
/// rendering the multipart MJPEG `/stream`.
///
/// WHY: Chrome stopped painting the robot's multipart/x-mixed-replace stream
/// (silently — no console error, no frames; 2026-07-24), both in an <img> and
/// as a top-level URL, while `/snapshot` serves valid JPEGs to everything (the
/// spine's face recognizer has consumed it flawlessly for weeks). Polling
/// snapshots removes the browser's MJPEG parser from the equation entirely and
/// behaves identically on web and native. `gaplessPlayback` keeps the frames
/// flicker-free.
class MjpegView extends StatefulWidget {
  /// Stream URL, e.g. `http://192.168.1.3:8080/stream` — the widget derives
  /// the snapshot endpoint from it, so existing call sites stay unchanged.
  final String url;
  final BoxFit fit;

  /// Kept for call-site compatibility (was needed for the web <img> readback);
  /// snapshot bytes are directly readable, so this is now a no-op.
  final bool crossOrigin;

  const MjpegView(
      {Key? key, required this.url, this.fit = BoxFit.cover, this.crossOrigin = false})
      : super(key: key);

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  static const _interval = Duration(milliseconds: 100); // ~10 fps
  Uint8List? _frame;
  Timer? _timer;
  bool _busy = false;
  int _consecutiveErrors = 0;

  String get _snapshotUrl => widget.url.replaceFirst('/stream', '/snapshot');

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_interval, (_) => _tick());
    _tick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      // Cache-buster: without it the browser serves the first snapshot from
      // HTTP cache forever ("frozen frame" — the endpoint sends no no-cache).
      final r = await http
          .get(Uri.parse(
              '$_snapshotUrl?ts=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 2));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty && mounted) {
        setState(() {
          _frame = r.bodyBytes;
          _consecutiveErrors = 0;
        });
      } else {
        _consecutiveErrors++;
      }
    } catch (_) {
      _consecutiveErrors++;
      // Keep polling — the camera comes back by itself after robot reboots.
      if (_consecutiveErrors == 20 && mounted) setState(() => _frame = null);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _consecutiveErrors > 20
              ? const Icon(Icons.videocam_off, size: 40, color: Colors.white24)
              : const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)),
          const SizedBox(height: 10),
          Text(
            _consecutiveErrors > 20 ? 'Camera unreachable — retrying…' : 'Connecting to camera…',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ]),
      );
    }
    return Image.memory(frame, fit: widget.fit, gaplessPlayback: true);
  }
}
