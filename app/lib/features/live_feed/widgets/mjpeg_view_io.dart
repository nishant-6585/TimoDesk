import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme.dart';
import 'mjpeg_parser.dart';

/// Mobile/desktop MJPEG renderer. Opens a streamed HTTP GET and slices out each
/// JPEG frame by its SOI (FF D8) … EOI (FF D9) markers — no multipart-boundary
/// parsing needed, which is the most robust way to decode CSJBot/MJPEG streams.
Widget buildMjpegView(BuildContext context, String url, BoxFit fit, {bool crossOrigin = false}) {
  // crossOrigin is a web-only concern (CORS on the <img>); ignored on io.
  return _MjpegStream(url: url, fit: fit);
}

class _MjpegStream extends StatefulWidget {
  final String url;
  final BoxFit fit;
  const _MjpegStream({required this.url, required this.fit});

  @override
  State<_MjpegStream> createState() => _MjpegStreamState();
}

class _MjpegStreamState extends State<_MjpegStream> {
  http.Client? _client;
  StreamSubscription<List<int>>? _sub;
  Uint8List? _frame;
  Object? _error;
  final List<int> _buffer = [];

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(_MjpegStream old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _teardown();
      _buffer.clear();
      _frame = null;
      _error = null;
      _connect();
    }
  }

  Future<void> _connect() async {
    try {
      _client = http.Client();
      final req = http.Request('GET', Uri.parse(widget.url));
      final resp = await _client!.send(req);
      if (!mounted) return;
      _sub = resp.stream.listen(
        _onData,
        onError: (e) {
          if (mounted) setState(() => _error = e);
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _onData(List<int> chunk) {
    _buffer.addAll(chunk);
    final frames = takeJpegFrames(_buffer);
    if (frames.isNotEmpty && mounted) {
      setState(() {
        _frame = frames.last; // render the freshest decoded frame
        _error = null;
      });
    }
  }

  void _teardown() {
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, size: 40, color: MikeeColors.error),
            const SizedBox(height: 8),
            Text('Camera offline',
                style: TextStyle(color: MikeeColors.textSecondary, fontSize: 12)),
          ],
        ),
      );
    }
    if (_frame == null) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2, color: MikeeColors.primary),
        ),
      );
    }
    return Image.memory(_frame!, fit: widget.fit, gaplessPlayback: true);
  }
}
