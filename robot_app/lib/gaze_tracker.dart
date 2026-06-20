import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

/// One detection result from the local (on-device) gaze pipeline.
///
/// ANONYMOUS — position/presence only, never identity (CHEST_UX_REDESIGN §3).
class GazeResult {
  final bool facePresent;
  final double gazeX; // -1..1 relative to frame center
  final double gazeY; // -1..1 relative to frame center
  const GazeResult(this.facePresent, this.gazeX, this.gazeY);

  static const GazeResult none = GazeResult(false, 0, 0);
}

/// Polls the robot's OWN /snapshot endpoint (NEVER opens a second camera —
/// CameraStreamPlugin owns camera2) and runs ML Kit face detection to drive the
/// avatar's eyes. Stores nothing: no frames, no logs, no embeddings.
///
/// On-device detection is for GAZE / PRESENCE only. Identity stays on spine
/// (Milestone D `face_detected`) — the two pipelines are never crossed.
class GazeTracker {
  GazeTracker({this.pollEvery = const Duration(milliseconds: 400)});

  final Duration pollEvery;

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    ),
  );

  // ── Gaze mapping (device-tunable — see HANDOFF #82 device-session notes) ────
  // gaze is derived from the face-box CENTER (not headEulerAngleY). On a
  // front-facing chest camera the snapshot may be mirrored, so the eyes could
  // track AWAY from the visitor — flip [_mirrorX] on the real robot to correct.
  // [_gazeYScale] damps vertical so the eyes don't slam to extremes when a face
  // is near the top/bottom of frame.
  static const bool _mirrorX = false;
  static const double _gazeXScale = 1.0;
  static const double _gazeYScale = 0.6;

  Timer? _timer;
  bool _busy = false;
  int? _imgW, _imgH;

  final _controller = StreamController<GazeResult>.broadcast();
  Stream<GazeResult> get results => _controller.stream;

  GazeResult _last = GazeResult.none;
  GazeResult get last => _last;

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(pollEvery, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    stop();
    await _detector.close();
    await _controller.close();
  }

  Future<void> _tick() async {
    if (_busy) return; // never overlap a poll
    _busy = true;
    try {
      final bytes = await _fetchSnapshot();
      if (bytes == null) {
        _emit(GazeResult.none);
        return;
      }
      if (_imgW == null) await _decodeDims(bytes);
      final res = await _detect(bytes);
      _emit(res);
    } catch (_) {
      // transient frame/detection error → treat as no face this cycle
      _emit(GazeResult.none);
    } finally {
      _busy = false;
    }
  }

  void _emit(GazeResult r) {
    _last = r;
    if (!_controller.isClosed) _controller.add(r);
  }

  Future<Uint8List?> _fetchSnapshot() async {
    try {
      final res = await http
          .get(Uri.parse('${RobotConfig.cameraBaseUrl}/snapshot'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return null;
      final b = res.bodyBytes;
      if (b.length < 4 || b[0] != 0xff || b[1] != 0xd8) return null; // JPEG SOI
      return b;
    } catch (_) {
      return null;
    }
  }

  Future<void> _decodeDims(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _imgW = frame.image.width;
      _imgH = frame.image.height;
      frame.image.dispose();
    } catch (_) {}
  }

  Future<GazeResult> _detect(Uint8List bytes) async {
    final w = _imgW, h = _imgH;
    if (w == null || h == null) return GazeResult.none;

    // ML Kit reads frame bytes via a temp file — it does NOT open the camera.
    final tmp = File('${Directory.systemTemp.path}/timo_gaze_frame.jpg');
    await tmp.writeAsBytes(bytes, flush: true);
    final faces = await _detector.processImage(InputImage.fromFilePath(tmp.path));
    if (faces.isEmpty) return GazeResult.none;

    // Largest face wins (closest / most relevant person).
    Face biggest = faces.first;
    for (final f in faces) {
      if (f.boundingBox.height > biggest.boundingBox.height) biggest = f;
    }

    final box = biggest.boundingBox;
    // Normalized box center → gaze, centered on the frame middle, ±1 at edges.
    final cx = box.center.dx / w; // 0..1
    final cy = box.center.dy / h; // 0..1
    double gazeX = (cx - 0.5) * 2 * _gazeXScale;
    if (_mirrorX) gazeX = -gazeX;
    final gazeY = (cy - 0.5) * 2 * _gazeYScale;
    return GazeResult(true, gazeX.clamp(-1.0, 1.0), gazeY.clamp(-1.0, 1.0));
  }
}
