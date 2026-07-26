import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

/// One detection result from the local (on-device) gaze pipeline.
///
/// ANONYMOUS — position/presence/pose only, never identity (CHEST_UX_REDESIGN §3).
class GazeResult {
  final bool facePresent;
  final double gazeX; // -1..1 relative to frame center
  final double gazeY; // -1..1 relative to frame center

  /// Attention gate: true only when the face has been LOOKING AT the camera
  /// (frontal head pose + near enough + eyes open) for [GazeTracker.dwellFrames]
  /// consecutive polls. This — not mere presence — is what triggers a greeting.
  final bool lookingAtCamera;

  // Raw gate inputs, surfaced for the debug overlay / on-site tuning.
  final double yawDeg; // head Euler Y — 0 = facing the camera
  final double faceRatio; // face-box height / frame height — proximity proxy

  const GazeResult(
    this.facePresent,
    this.gazeX,
    this.gazeY, {
    this.lookingAtCamera = false,
    this.yawDeg = 0,
    this.faceRatio = 0,
  });

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
      // Eye-open probabilities for the attention gate (head Euler Y/Z come free).
      enableClassification: true,
    ),
  );

  // ── Attention gate (greet only when looking at the camera) ─────────────────
  // Frontal yaw + proximity thresholds live in RobotConfig (Settings-tunable);
  // roll / eye-open / dwell are fixed here. Eye-open is null-safe: when ML Kit
  // can't score the eyes (small/backlit face) the check passes rather than
  // silencing greetings entirely.
  static const double _maxRollDeg = 20;
  static const double _minEyeOpen = 0.3;

  /// Consecutive looking-at-camera polls required before the gate opens
  /// (2 × 400ms poll ≈ 0.8s of deliberate attention — filters walk-pasts).
  static const int dwellFrames = 2;
  int _lookStreak = 0;

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
        if (kDebugMode) debugPrint('GazeDiag: snapshot=null (${RobotConfig.cameraBaseUrl}/snapshot — server/camera down?)');
        _emit(GazeResult.none);
        return;
      }
      if (_imgW == null) await _decodeDims(bytes);
      final res = await _detect(bytes);
      if (kDebugMode) {
        debugPrint('GazeDiag: snap=${bytes.length}B ${_imgW}x${_imgH} '
            'facePresent=${res.facePresent} gaze=(${res.gazeX.toStringAsFixed(2)},${res.gazeY.toStringAsFixed(2)})');
      }
      _emit(res);
    } catch (_) {
      // transient frame/detection error → treat as no face this cycle
      _emit(GazeResult.none);
    } finally {
      _busy = false;
    }
  }

  void _emit(GazeResult r) {
    if (!r.facePresent) _lookStreak = 0; // covers snapshot/detector failures too
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
    final tmp = File('${Directory.systemTemp.path}/mikee_gaze_frame.jpg');
    await tmp.writeAsBytes(bytes, flush: true);
    final faces = await _detector.processImage(InputImage.fromFilePath(tmp.path));
    if (faces.isEmpty) {
      _lookStreak = 0;
      return GazeResult.none;
    }

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

    // Attention gate: frontal head pose + close enough + eyes open, sustained
    // for [dwellFrames] polls. abs(yaw) is mirroring-proof.
    final yaw = biggest.headEulerAngleY ?? 0;
    final roll = biggest.headEulerAngleZ ?? 0;
    final faceRatio = box.height / h;
    final le = biggest.leftEyeOpenProbability;
    final re = biggest.rightEyeOpenProbability;
    final eyesOpen =
        (le == null || re == null) ? true : (le > _minEyeOpen || re > _minEyeOpen);
    final lookingNow = yaw.abs() <= RobotConfig.attentionMaxYawDeg &&
        roll.abs() <= _maxRollDeg &&
        faceRatio >= RobotConfig.attentionMinFaceRatio &&
        eyesOpen;
    _lookStreak = lookingNow ? _lookStreak + 1 : 0;

    return GazeResult(
      true,
      gazeX.clamp(-1.0, 1.0),
      gazeY.clamp(-1.0, 1.0),
      lookingAtCamera: _lookStreak >= dwellFrames,
      yawDeg: yaw,
      faceRatio: faceRatio,
    );
  }
}
