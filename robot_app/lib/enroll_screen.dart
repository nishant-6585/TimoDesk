import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

// ── Config ──────────────────────────────────────────────────────────────────
// Spine + camera base URLs now live in RobotConfig (persisted, editable in the
// Settings dashboard tile). The robot serves its OWN camera (CameraStreamPlugin /
// camera2) — we REUSE /snapshot, never open a second camera.

// Bearer token the kiosk sends to spine. In dev this is the bypass token (works
// only behind spine's DEV_AUTH_BYPASS).
//
// TODO(auth go-live): the kiosk must obtain + refresh a REAL Supabase operator
// access token — sign in a dedicated kiosk account via
// supabase.auth.signInWithPassword and send its ES256 access_token here (same
// JWKS verify path as the admin app). Once spine's bypass is off, this literal
// stops working. Source from config/secure storage, not a hardcoded constant.
const String kKioskDevToken = 'test-token';
const String kAuthToken = kKioskDevToken;

const _orange = Color(0xFFFF6B35);

// ── Pose plan ───────────────────────────────────────────────────────────────
class _Pose {
  final String name; // also the frame label
  final String instruction;
  const _Pose(this.name, this.instruction);
}

const List<_Pose> _posePlan = [
  _Pose('Front', 'Look straight at the screen'),
  _Pose('Left', 'Slowly turn your head to your LEFT'),
  _Pose('Right', 'Slowly turn your head to your RIGHT'),
  _Pose('Up', 'Tilt your head UP'),
  _Pose('Down', 'Tilt your head DOWN'),
];

// ── Screen ──────────────────────────────────────────────────────────────────
class EnrollScreen extends StatefulWidget {
  const EnrollScreen({super.key});

  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  // Tunable gates.
  static const double _minFaceHeight = 0.28; // fraction of frame height
  static const double _maxFaceHeight = 0.90;
  static const double _yawTurn = 18; // degrees for Left/Right
  static const double _yawFront = 10;
  static const double _pitchTurn = 12; // degrees for Up/Down
  static const double _pitchFront = 10;
  static const int _stableNeeded = 4; // consecutive good frames (~1s at 250ms)
  static const int _getReadySeconds = 3;
  static const Duration _pollEvery = Duration(milliseconds: 250);

  // Phases: form → capture → uploading → done
  String _phase = 'form';

  // Form
  final _nameCtr = TextEditingController();
  final _phoneCtr = TextEditingController();
  String _personType = 'Employee';
  bool _consent = false;

  // Capture
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast, minFaceSize: 0.15),
  );
  Timer? _pollTimer;
  Timer? _getReadyTimer;
  bool _detecting = false;
  Uint8List? _latestFrame; // most recent /snapshot bytes (preview + capture)
  int? _imgW;
  int? _imgH;

  int _poseIndex = 0;
  String _capPhase = 'getReady'; // getReady | detecting | captured | checking
  int _getReadyLeft = _getReadySeconds;
  int _stable = 0;
  bool _faceReady = false;
  String _hint = 'Starting…';
  final List<Uint8List> _frames = [];

  // Upload
  String _uploadMsg = '';
  String? _doneError;

  _Pose get _pose => _posePlan[_poseIndex];

  @override
  void dispose() {
    _pollTimer?.cancel();
    _getReadyTimer?.cancel();
    _detector.close();
    _nameCtr.dispose();
    _phoneCtr.dispose();
    super.dispose();
  }

  // ── Capture flow ──────────────────────────────────────────────────────────
  void _startCapture() {
    setState(() {
      _phase = 'capture';
      _poseIndex = 0;
      _frames.clear();
    });
    _pollTimer = Timer.periodic(_pollEvery, (_) => _tick());
    _startPose();
  }

  void _startPose() {
    _getReadyTimer?.cancel();
    setState(() {
      _capPhase = 'getReady';
      _getReadyLeft = _getReadySeconds;
      _stable = 0;
      _faceReady = false;
    });
    _getReadyTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _getReadyLeft--);
      if (_getReadyLeft <= 0) {
        t.cancel();
        setState(() => _capPhase = 'detecting');
      }
    });
  }

  // One poll cycle: fetch a snapshot, update preview, run detection.
  Future<void> _tick() async {
    if (_detecting) return;
    _detecting = true;
    try {
      final bytes = await _fetchSnapshot();
      if (bytes == null || !mounted) return;
      _latestFrame = bytes;
      if (_imgW == null) await _decodeDims(bytes);
      // Only the live preview updates outside the detecting phase.
      if (_capPhase != 'detecting') {
        setState(() {});
        return;
      }
      await _detectAndGate(bytes);
    } catch (_) {
      // ignore transient frame errors
    } finally {
      _detecting = false;
    }
  }

  Future<Uint8List?> _fetchSnapshot() async {
    try {
      final res = await http
          .get(Uri.parse('${RobotConfig.cameraBaseUrl}/snapshot'))
          .timeout(const Duration(seconds: 4));
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

  // Detect faces on the frame and decide if the current pose is satisfied.
  Future<void> _detectAndGate(Uint8List bytes) async {
    final w = _imgW, h = _imgH;
    if (w == null || h == null) return;

    // ML Kit reads frame bytes via a temp file — it does NOT open the camera.
    final tmp = File('${Directory.systemTemp.path}/timo_enroll_frame.jpg');
    await tmp.writeAsBytes(bytes, flush: true);
    final faces = await _detector.processImage(InputImage.fromFilePath(tmp.path));

    String hint;
    bool ready = false;
    if (faces.isEmpty) {
      hint = 'No face detected';
    } else if (faces.length > 1) {
      hint = 'Only one face, please';
    } else {
      final f = faces.first;
      final box = f.boundingBox;
      final faceH = box.height / h;
      final cx = box.center.dx / w;
      final cy = box.center.dy / h;
      final yaw = f.headEulerAngleY ?? 0; // +/- left-right (flip below if reversed)
      final pitch = f.headEulerAngleX ?? 0; // +/- up-down

      final sized = faceH >= _minFaceHeight && faceH <= _maxFaceHeight;
      final centered = cx > 0.3 && cx < 0.7 && cy > 0.25 && cy < 0.75;
      final orientationOk = _orientationMatches(_pose.name, yaw, pitch);

      if (!sized) {
        hint = faceH < _minFaceHeight ? 'Move closer' : 'Move back';
      } else if (!centered) {
        hint = 'Center your face';
      } else if (!orientationOk) {
        hint = _pose.instruction;
      } else {
        hint = 'Hold still…';
        ready = true;
      }
    }

    if (!mounted) return;
    setState(() {
      _faceReady = ready;
      _hint = hint;
      _stable = ready ? _stable + 1 : 0;
    });

    if (ready && _stable >= _stableNeeded && _capPhase == 'detecting') {
      _capture();
    }
  }

  // NOTE: if Left/Right or Up/Down feel swapped on the real robot camera, flip
  // the comparisons here — this is the only place orientation sign is decided.
  bool _orientationMatches(String pose, double yaw, double pitch) {
    switch (pose) {
      case 'Front':
        return yaw.abs() < _yawFront && pitch.abs() < _pitchFront;
      case 'Left':
        return yaw >= _yawTurn;
      case 'Right':
        return yaw <= -_yawTurn;
      case 'Up':
        return pitch >= _pitchTurn;
      case 'Down':
        return pitch <= -_pitchTurn;
    }
    return false;
  }

  Future<void> _capture() async {
    final frame = _latestFrame;
    if (frame == null) return;
    setState(() => _capPhase = 'captured');
    _frames.add(frame);

    // Duplicate guard after the FIRST pose (clean frontal frame).
    if (_poseIndex == 0) {
      setState(() => _capPhase = 'checking');
      final dup = await _checkDuplicate(frame);
      if (!mounted) return;
      if (dup != null) {
        final proceed = await _showDuplicateDialog(dup);
        if (!mounted) return;
        if (!proceed) {
          _pollTimer?.cancel();
          _getReadyTimer?.cancel();
          Navigator.of(context).pop();
          return;
        }
      }
    }

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    if (_poseIndex < _posePlan.length - 1) {
      setState(() => _poseIndex++);
      _startPose();
    } else {
      _pollTimer?.cancel();
      _getReadyTimer?.cancel();
      _upload();
    }
  }

  // ── Backend ───────────────────────────────────────────────────────────────
  Future<String?> _checkDuplicate(Uint8List frame) async {
    try {
      final res = await http
          .post(
            Uri.parse('${RobotConfig.spineBaseUrl}/check-face'),
            headers: {'Authorization': 'Bearer $kAuthToken', 'Content-Type': 'application/json'},
            body: jsonEncode({'image_base64': base64Encode(frame)}),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] == true && data['match'] == true) return data['name'] as String?;
    } catch (_) {}
    return null; // fail open
  }

  Future<bool> _showDuplicateDialog(String name) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Already enrolled'),
        content: Text('This face looks like $name is already enrolled.\nStop, or continue anyway?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stop')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue anyway'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  Future<void> _upload() async {
    setState(() {
      _phase = 'uploading';
      _doneError = null;
    });
    final consentRef = 'robot-consent-${DateTime.now().toIso8601String()}';
    int ok = 0;
    for (var i = 0; i < _frames.length; i++) {
      setState(() => _uploadMsg = 'Saving pose ${i + 1} of ${_frames.length}…');
      try {
        final res = await http
            .post(
              Uri.parse('${RobotConfig.spineBaseUrl}/enroll'),
              headers: {'Authorization': 'Bearer $kAuthToken', 'Content-Type': 'application/json'},
              body: jsonEncode({
                'full_name': _nameCtr.text,
                'phone': _phoneCtr.text,
                'person_type': _personType,
                'consent': true,
                'consent_ref': '$consentRef-pose-$i',
                'image_base64': base64Encode(_frames[i]),
              }),
            )
            .timeout(const Duration(seconds: 30));
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['ok'] == true) ok++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _phase = 'done';
      _doneError = ok == 0 ? 'Enrollment failed — could not reach spine.' : null;
      _uploadMsg = 'Saved $ok of ${_frames.length} poses';
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll Staff', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1A1A),
        centerTitle: true,
      ),
      body: switch (_phase) {
        'form' => _buildForm(),
        'capture' => _buildCapture(),
        'uploading' => _buildUploading(),
        _ => _buildDone(),
      },
    );
  }

  Widget _buildForm() {
    final canStart = _nameCtr.text.trim().isNotEmpty && _consent;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Enter your details, then capture 5 quick poses.',
            style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 20),
        TextField(
          controller: _nameCtr,
          style: const TextStyle(fontSize: 18),
          decoration: _dec('Full name *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneCtr,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontSize: 18),
          decoration: _dec('Phone'),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _personType,
          dropdownColor: const Color(0xFF1A1A1A),
          decoration: _dec('Person type'),
          items: const [
            DropdownMenuItem(value: 'Employee', child: Text('Employee')),
            DropdownMenuItem(value: 'Staff', child: Text('Staff')),
          ],
          onChanged: (v) => setState(() => _personType = v ?? 'Employee'),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _consent,
          activeColor: _orange,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('I consent to enroll my face for identification'),
          onChanged: (v) => setState(() => _consent = v ?? false),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: canStart ? _startCapture : null,
          icon: const Icon(Icons.camera_alt_rounded),
          label: const Text('START FACE CAPTURE',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
          style: FilledButton.styleFrom(
            backgroundColor: _orange,
            padding: const EdgeInsets.symmetric(vertical: 18),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
      ]),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _buildCapture() {
    final border = _capPhase == 'captured' || _faceReady ? const Color(0xFF4ADE80) : _orange;
    return Column(children: [
      Expanded(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: border, width: 3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(fit: StackFit.expand, children: [
              if (_latestFrame != null)
                Image.memory(_latestFrame!, fit: BoxFit.cover, gaplessPlayback: true)
              else
                const Center(child: CircularProgressIndicator()),
              Container(color: Colors.black.withValues(alpha: 0.2)),
              Center(child: _captureCenter()),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _captureCenter() {
    if (_capPhase == 'getReady') {
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('Step ${_poseIndex + 1} of ${_posePlan.length}',
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 8),
        Text(_pose.name.toUpperCase(),
            style: const TextStyle(color: _orange, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 12),
        Text(_pose.instruction,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        CircleAvatar(radius: 34, backgroundColor: Colors.black45, child: Text('$_getReadyLeft',
            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold))),
      ]);
    }
    if (_capPhase == 'checking') {
      return const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
        SizedBox(height: 16),
        Text('Checking if already enrolled…',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ]);
    }
    if (_capPhase == 'captured') {
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.check_circle, size: 80, color: Color(0xFF4ADE80)),
        const SizedBox(height: 12),
        Text('Captured ${_pose.name}',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      ]);
    }
    // detecting
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('Step ${_poseIndex + 1} of ${_posePlan.length}',
          style: const TextStyle(color: Colors.white70, fontSize: 14)),
      const SizedBox(height: 8),
      Text(_pose.instruction,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      Icon(_faceReady ? Icons.check_circle : Icons.face, size: 72,
          color: _faceReady ? const Color(0xFF4ADE80) : _orange),
      const SizedBox(height: 14),
      Text(_hint, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      if (_faceReady) ...[
        const SizedBox(height: 10),
        SizedBox(width: 160, child: LinearProgressIndicator(
          value: (_stable / _stableNeeded).clamp(0.0, 1.0),
          backgroundColor: Colors.white24,
          valueColor: const AlwaysStoppedAnimation(Color(0xFF4ADE80)),
        )),
      ],
    ]);
  }

  Widget _buildUploading() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(color: _orange),
          const SizedBox(height: 20),
          Text(_uploadMsg, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ]),
      );

  Widget _buildDone() {
    final ok = _doneError == null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(ok ? Icons.check_circle : Icons.error, size: 96,
              color: ok ? const Color(0xFF4ADE80) : Colors.redAccent),
          const SizedBox(height: 20),
          Text(ok ? 'Enrolled!' : 'Enrollment failed',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_doneError ?? '${_nameCtr.text} · $_uploadMsg',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
                backgroundColor: _orange, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16)),
            child: const Text('DONE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
        ]),
      ),
    );
  }
}
