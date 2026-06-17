import 'dart:typed_data';
import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../settings/providers/settings_provider.dart';
import '../../staff/providers/enrollment_provider.dart';
import '../../staff/screens/staff_list_screen.dart';
import '../widgets/mjpeg_view.dart';
import '../widgets/enroll_webcam_view.dart';

/// Where enrollment reads frames from.
enum _EnrollSource { device, robot }

class LiveFeedScreen extends ConsumerStatefulWidget {
  const LiveFeedScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends ConsumerState<LiveFeedScreen> {
  bool _enrollmentMode = false;
  bool _streaming = false;
  // Default to this device's webcam in the browser so the person, the camera,
  // and the on-screen guidance are all in one place.
  _EnrollSource _enrollSource = _EnrollSource.device;

  void _toggleEnrollmentMode() {
    setState(() {
      _enrollmentMode = !_enrollmentMode;
      // Robot-source enrollment needs the MJPEG running; device-source uses the
      // webcam which starts itself.
      if (_enrollmentMode && _enrollSource == _EnrollSource.robot) _streaming = true;
    });
  }

  // The detection overlay should run once the chosen source is showing frames.
  bool get _overlayActive {
    if (!_enrollmentMode) return false;
    return _enrollSource == _EnrollSource.device || _streaming;
  }

  // Which media element fills the camera box right now.
  Widget _buildCameraLayer(String url) {
    if (_enrollmentMode && _enrollSource == _EnrollSource.device) {
      return const DeviceWebcamView();
    }
    if (_streaming) return MjpegView(url: url);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off, size: 64, color: Color(0xFF3A3A3A)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => setState(() => _streaming = true),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Stream'),
          ),
        ],
      ),
    );
  }

  void _onFramesCaptured(List<Uint8List> frames) {
    setState(() => _enrollmentMode = false);
    _showEnrollmentForm(frames);
  }

  void _showEnrollmentForm(List<Uint8List> capturedFrames) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: _EnrollmentFormModal(capturedFrames: capturedFrames),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final robotIp = ref.watch(settingsProvider).robotIp;
    final url = robotStreamUrl(robotIp);

    return Scaffold(
      backgroundColor: TimoColors.background,
      appBar: AppBar(
        title: const Text('Live Feed'),
        backgroundColor: TimoColors.surface,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StaffListScreen()),
            ),
            icon: const Icon(Icons.group),
            label: const Text('Manage Staff'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _toggleEnrollmentMode,
            icon: const Icon(Icons.person_add),
            label: Text(_enrollmentMode ? 'Cancel' : 'Enroll Staff'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 700),
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: TimoColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              // Live camera feed
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.black87,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _streaming ? TimoColors.error : TimoColors.textMuted,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _streaming ? 'LIVE' : 'OFFLINE',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _streaming ? TimoColors.error : TimoColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          // Camera-source toggle (enrollment only).
                          if (_enrollmentMode)
                            _SourceToggle(
                              source: _enrollSource,
                              onChanged: (s) => setState(() {
                                _enrollSource = s;
                                if (s == _EnrollSource.robot) _streaming = true;
                              }),
                            ),
                          InkWell(
                            onTap: () => setState(() => _streaming = !_streaming),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                _streaming ? Icons.stop_circle : Icons.play_circle,
                                size: 24,
                                color: _streaming ? TimoColors.error : TimoColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Camera view
                    Expanded(
                      child: Stack(
                        children: [
                          _buildCameraLayer(url),
                          // Enrollment detection overlay — target the webcam <video>
                          // (device) or the MJPEG <img> (robot).
                          if (_overlayActive)
                            _EnrollmentDetectionOverlay(
                              elementSelector: _enrollSource == _EnrollSource.device
                                  ? '#$kEnrollWebcamId'
                                  : 'img[src*="$url"]',
                              onFramesCaptured: _onFramesCaptured,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact segmented toggle: "This device" vs "Robot" camera for enrollment.
class _SourceToggle extends StatelessWidget {
  final _EnrollSource source;
  final ValueChanged<_EnrollSource> onChanged;
  const _SourceToggle({required this.source, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(_EnrollSource s, IconData icon, String label) {
      final active = source == s;
      return InkWell(
        onTap: () => onChanged(s),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? TimoColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: active ? Colors.white : TimoColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : TimoColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: TimoColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(_EnrollSource.device, Icons.laptop, 'This device'),
          const SizedBox(width: 2),
          seg(_EnrollSource.robot, Icons.smart_toy, 'Robot'),
        ],
      ),
    );
  }
}

/// Face detection overlay for multi-capture enrollment (5 poses).
/// [elementSelector] is the CSS selector of the media element to read frames
/// from — the MJPEG <img> (robot) or the webcam <video> (this device). face-api
/// and canvas capture work identically on either.
class _EnrollmentDetectionOverlay extends StatefulWidget {
  final String elementSelector;
  final Function(List<Uint8List>) onFramesCaptured;

  const _EnrollmentDetectionOverlay({
    required this.elementSelector,
    required this.onFramesCaptured,
  });

  @override
  State<_EnrollmentDetectionOverlay> createState() => _EnrollmentDetectionOverlayState();
}

// One enrollment pose: the label stored with the frame + the on-screen instruction.
class _Pose {
  final String name; // Front / Left / Right / Up / Down (also the frame label)
  final String instruction; // shown to the user during get-ready
  const _Pose(this.name, this.instruction);
}

class _EnrollmentDetectionOverlayState extends State<_EnrollmentDetectionOverlay> {
  // ---- Tunable gates (adjust here, nowhere else) ----
  // Face height as a fraction of frame height. Bigger = sharper, more
  // discriminative embeddings. face-api recognition degrades on small faces,
  // so require the face to fill a good chunk of the frame (≈145px+ at 480p).
  static const double _minFaceHeight = 0.30; // below this → "move closer"
  static const double _maxFaceHeight = 0.80; // above this → "move back"
  // Head orientation thresholds (from landmarks; see _describeOrientation).
  // Keep turns MILD — a strong profile becomes undetectable server-side and
  // makes a poor recognition embedding. Slight turns give enough variation.
  static const double _yawFront = 0.10; // |yaw| under this = facing front
  static const double _yawTurn = 0.15; // |yaw| over this = (slightly) turned left/right
  static const double _noseRelFront = 0.48; // front baseline of nose-between-eyes-and-mouth
  static const double _pitchDelta = 0.10; // how far nose must move for up/down
  // How long the face must hold the correct pose before capture (~1.0s at
  // 100ms). Longer hold = the head has settled = less motion blur.
  static const int _stabilityThreshold = 10;
  // Get-ready countdown before each pose (seconds).
  static const int _getReadySeconds = 3;

  static const List<_Pose> _posePlan = [
    _Pose('Front', 'Look straight at the camera'),
    _Pose('Left', 'Slowly turn your head to your LEFT'),
    _Pose('Right', 'Slowly turn your head to your RIGHT'),
    _Pose('Up', 'Tilt your head UP (chin up)'),
    _Pose('Down', 'Tilt your head DOWN (chin down)'),
  ];

  bool _modelsLoaded = false;
  Timer? _detectionTimer;
  Timer? _getReadyTimer;
  int _stableFrames = 0;

  // Capture state machine: getReady → detecting → captured → (next) → done
  String _phase = 'getReady';
  int _getReadyLeft = _getReadySeconds;
  int _currentPoseIndex = 0;
  final List<Uint8List> _capturedFrames = [];

  // Live detection readout (for UI feedback)
  bool _faceDetected = false;
  String _status = 'Center your face';
  String _detectedOrientation = '';

  _Pose get _currentPose => _posePlan[_currentPoseIndex];

  @override
  void initState() {
    super.initState();
    _initializeAndDetect();
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _getReadyTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeAndDetect() async {
    await _loadFaceApiModels();
    if (!mounted) return;

    // Continuous detection loop (live feedback always; capture only when detecting).
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) _detectAndCapture();
    });

    _startPose(); // begin with the get-ready countdown for pose 0
  }

  // Begin a pose with a get-ready countdown so the user can reposition.
  void _startPose() {
    _getReadyTimer?.cancel();
    setState(() {
      _phase = 'getReady';
      _getReadyLeft = _getReadySeconds;
      _stableFrames = 0;
      _faceDetected = false;
    });
    _getReadyTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _getReadyLeft--);
      if (_getReadyLeft <= 0) {
        t.cancel();
        setState(() {
          _phase = 'detecting';
          _stableFrames = 0;
        });
      }
    });
  }

  Future<void> _loadFaceApiModels() async {
    try {
      final modelUrl = 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@latest/model/';
      final jsCode = '''(async function() {
        const script = document.createElement('script');
        script.src = 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@latest/dist/face-api.min.js';
        document.head.appendChild(script);

        return new Promise(resolve => {
          script.onload = async () => {
            await faceapi.nets.tinyFaceDetector.loadFromUri('$modelUrl');
            await faceapi.nets.faceLandmark68Net.loadFromUri('$modelUrl');
            await faceapi.nets.faceRecognitionNet.loadFromUri('$modelUrl');
            resolve(true);
          };
        });
      })()''';

      final result = await js.context.callMethod('eval', [jsCode]);
      final completer = Completer<bool>();
      result.callMethod('then', [(val) => completer.complete(true)]).callMethod('catch', [(err) {
        completer.complete(false);
      }]);

      await completer.future;
      if (mounted) {
        setState(() => _modelsLoaded = true);
      }
    } catch (err) {
      print('[EnrollmentDetection] Model load error: $err');
    }
  }

  // Decide if the measured head orientation satisfies the requested pose.
  bool _poseOrientationMatches(String pose, double yaw, double noseRel) {
    switch (pose) {
      case 'Front':
        return yaw.abs() < _yawFront && (noseRel - _noseRelFront).abs() < _pitchDelta;
      case 'Left':
        // NOTE: sign convention — if Left/Right feel swapped on the real camera,
        // flip the comparisons here (the only place orientation sign is decided).
        return yaw <= -_yawTurn;
      case 'Right':
        return yaw >= _yawTurn;
      case 'Up':
        return noseRel <= _noseRelFront - _pitchDelta;
      case 'Down':
        return noseRel >= _noseRelFront + _pitchDelta;
    }
    return false;
  }

  String _describeOrientation(double yaw, double noseRel) {
    if (yaw <= -_yawTurn) return 'turned left';
    if (yaw >= _yawTurn) return 'turned right';
    if (noseRel <= _noseRelFront - _pitchDelta) return 'tilted up';
    if (noseRel >= _noseRelFront + _pitchDelta) return 'tilted down';
    return 'facing front';
  }

  void _detectAndCapture() {
    if (!_modelsLoaded) return;

    try {
      // Detect 1 face + landmarks; compute size, centering, yaw and a pitch proxy.
      // Works for both <img> (MJPEG) and <video> (webcam) — dimensions come from
      // naturalWidth/Height (img) or videoWidth/Height (video).
      final jsDetectionCode = '''(async function() {
        const el = document.querySelector('${widget.elementSelector}');
        const elW = el ? (el.naturalWidth || el.videoWidth || 0) : 0;
        const elH = el ? (el.naturalHeight || el.videoHeight || 0) : 0;
        if (!el || elW === 0) return {faces: 0};
        try {
          const dets = await faceapi
            .detectAllFaces(el, new faceapi.TinyFaceDetectorOptions())
            .withFaceLandmarks();
          if (dets.length !== 1) return {faces: dets.length};

          const d = dets[0];
          const box = d.detection.box;
          const imgW = elW, imgH = elH;

          const lm = d.landmarks;
          const avg = (pts) => { let x=0,y=0; for (const p of pts){x+=p.x;y+=p.y;} return {x:x/pts.length, y:y/pts.length}; };
          const leC = avg(lm.getLeftEye());
          const reC = avg(lm.getRightEye());
          const mC  = avg(lm.getMouth());
          const nose = lm.getNose();          // points 27..35
          const noseTip = nose[3] || nose[nose.length-1]; // ~point 30
          const eyeMid = { x:(leC.x+reC.x)/2, y:(leC.y+reC.y)/2 };
          const interEye = Math.hypot(reC.x-leC.x, reC.y-leC.y) || 1;
          const faceVert = (mC.y - eyeMid.y) || 1;

          return {
            faces: 1,
            faceHeight: box.height / imgH,
            centerX: (box.x + box.width/2) / imgW,
            centerY: (box.y + box.height/2) / imgH,
            yaw: (noseTip.x - eyeMid.x) / interEye,        // -left .. +right
            noseRel: (noseTip.y - eyeMid.y) / faceVert     // ~0.48 front, smaller=up, larger=down
          };
        } catch(e) { return {faces: 0}; }
      })()''';

      final jsFunc = js.context.callMethod('eval', [jsDetectionCode]);
      final completer = Completer<Map<String, dynamic>>();

      jsFunc.callMethod('then', [(result) {
        double toD(dynamic v) => (v is num) ? v.toDouble() : 0.0;
        try {
          completer.complete({
            'faces': (result['faces'] is num) ? (result['faces'] as num).toInt() : 0,
            'faceHeight': toD(result['faceHeight']),
            'centerX': toD(result['centerX']),
            'centerY': toD(result['centerY']),
            'yaw': toD(result['yaw']),
            'noseRel': toD(result['noseRel']),
          });
        } catch (e) {
          completer.complete({'faces': 0});
        }
      }]).callMethod('catch', [(err) {
        completer.complete({'faces': 0});
      }]);

      completer.future.then((r) {
        if (!mounted) return;

        final faces = r['faces'] as int? ?? 0;
        final faceH = r['faceHeight'] as double? ?? 0.0;
        final cx = r['centerX'] as double? ?? 0.0;
        final cy = r['centerY'] as double? ?? 0.0;
        final yaw = r['yaw'] as double? ?? 0.0;
        final noseRel = r['noseRel'] as double? ?? 0.0;

        // Geometry gates shared by all poses.
        final sized = faceH >= _minFaceHeight && faceH <= _maxFaceHeight;
        final centered = cx > 0.25 && cx < 0.75 && cy > 0.2 && cy < 0.8;
        final orientationOk = _poseOrientationMatches(_currentPose.name, yaw, noseRel);
        final ready = faces == 1 && sized && centered && orientationOk;

        // Build the live hint.
        String hint;
        if (faces == 0) {
          hint = 'No face detected';
        } else if (faces > 1) {
          hint = 'Only one face allowed';
        } else if (!sized) {
          hint = faceH < _minFaceHeight ? 'Move closer' : 'Move back';
        } else if (!centered) {
          hint = 'Center your face';
        } else if (!orientationOk) {
          hint = _currentPose.instruction;
        } else {
          hint = 'Hold still…';
        }

        setState(() {
          _faceDetected = ready;
          _detectedOrientation = faces == 1 ? _describeOrientation(yaw, noseRel) : '';
          _status = hint;
          // Only accumulate stability while actively detecting this pose.
          if (_phase == 'detecting' && ready) {
            _stableFrames++;
          } else {
            _stableFrames = 0;
          }
        });

        if (_phase == 'detecting' && ready && _stableFrames >= _stabilityThreshold) {
          _captureFrame();
        }
      });
    } catch (err) {
      print('[EnrollmentDetection] Detection error: $err');
    }
  }

  Future<void> _captureFrame() async {
    // Enter captured phase immediately so the detection loop stops trying to capture.
    setState(() {
      _phase = 'captured';
      _stableFrames = 0;
    });

    try {
      final captureCode = '''(async function() {
        const el = document.querySelector('${widget.elementSelector}');
        if (!el) return null;
        const w = el.naturalWidth || el.videoWidth || 0;
        const h = el.naturalHeight || el.videoHeight || 0;
        if (w === 0) return null;

        const canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(el, 0, 0);

        return canvas.toDataURL('image/jpeg', 0.9);
      })()''';

      final jsFunc = js.context.callMethod('eval', [captureCode]);
      final completer = Completer<String?>();

      jsFunc.callMethod('then', [(dataUrl) {
        completer.complete(dataUrl as String?);
      }]).callMethod('catch', [(err) {
        completer.complete(null);
      }]);

      final dataUrl = await completer.future;
      if (dataUrl != null && dataUrl.isNotEmpty) {
        final base64 = dataUrl.split(',').last;
        final bytes = base64Decode(base64);

        if (mounted) {
          setState(() {
            _capturedFrames.add(bytes);
            _status = '✓ Captured ${_currentPose.name}';
            _faceDetected = true;
          });

          // Brief confirmation pause, then get-ready for the next pose.
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (!mounted) return;
            if (_currentPoseIndex < _posePlan.length - 1) {
              setState(() => _currentPoseIndex++);
              _startPose();
            } else {
              setState(() => _phase = 'done');
              _detectionTimer?.cancel();
              _getReadyTimer?.cancel();
              widget.onFramesCaptured(_capturedFrames);
            }
          });
        }
      } else {
        // Capture failed — fall back to detecting so we retry this pose.
        if (mounted) setState(() => _phase = 'detecting');
      }
    } catch (err) {
      print('[EnrollmentDetection] Capture error: $err');
      if (mounted) setState(() => _phase = 'detecting');
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _phase == 'captured'
        ? Colors.green
        : (_faceDetected ? Colors.green : Colors.orange);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 3),
      ),
      child: Stack(
        children: [
          Container(color: Colors.black.withOpacity(0.25)),
          Center(child: _buildCenterContent()),
          // Live orientation readout, bottom-left.
          if (_modelsLoaded && _detectedOrientation.isNotEmpty)
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Detected: $_detectedOrientation',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCenterContent() {
    if (!_modelsLoaded) {
      return Text(
        'Loading face detection…',
        style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      );
    }

    // Get-ready: big instruction + countdown, no capture yet.
    if (_phase == 'getReady') {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Step ${_currentPoseIndex + 1} of ${_posePlan.length}',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 10),
          Text(_currentPose.name.toUpperCase(),
              style: GoogleFonts.inter(color: TimoColors.primary, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 14),
          Text(_currentPose.instruction,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Container(
            width: 72, height: 72,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black45),
            child: Center(
              child: Text('$_getReadyLeft',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          Text('Get ready…', style: GoogleFonts.inter(color: Colors.white70, fontSize: 14)),
        ],
      );
    }

    // Captured confirmation.
    if (_phase == 'captured') {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 90, color: Colors.green),
          const SizedBox(height: 16),
          Text('Captured ${_currentPose.name}',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      );
    }

    // Detecting: instruction + live hint + stability progress.
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Step ${_currentPoseIndex + 1} of ${_posePlan.length}',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 8),
        Text(_currentPose.instruction,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 18),
        Icon(_faceDetected ? Icons.check_circle : Icons.face,
            size: 80, color: _faceDetected ? Colors.green : Colors.orange),
        const SizedBox(height: 16),
        Text(_status,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        if (_faceDetected) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: 160,
            child: LinearProgressIndicator(
              value: (_stableFrames / _stabilityThreshold).clamp(0.0, 1.0),
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.green),
            ),
          ),
        ],
      ],
    );
  }
}

/// Enrollment form modal with multiple captured frames
class _EnrollmentFormModal extends ConsumerStatefulWidget {
  final List<Uint8List> capturedFrames;

  const _EnrollmentFormModal({required this.capturedFrames});

  @override
  ConsumerState<_EnrollmentFormModal> createState() => _EnrollmentFormModalState();
}

class _EnrollmentFormModalState extends ConsumerState<_EnrollmentFormModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtr = TextEditingController();
  final _phoneCtr = TextEditingController();
  final _roleCtr = TextEditingController();
  String _personType = 'Employee';
  bool _consent = false;
  bool _enrolling = false;

  @override
  void dispose() {
    _nameCtr.dispose();
    _phoneCtr.dispose();
    _roleCtr.dispose();
    super.dispose();
  }

  Future<void> _submitEnrollment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enrolling = true);

    final notifier = ref.read(enrollmentProvider.notifier);

    // Duplicate guard: does this face already belong to an enrolled person?
    if (widget.capturedFrames.isNotEmpty) {
      final check = await notifier.checkFace(widget.capturedFrames.first);
      if (check.match && mounted) {
        setState(() => _enrolling = false);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: TimoColors.surface,
            title: const Text('Already enrolled?'),
            content: Text(
              'This face looks like ${check.name} is already enrolled'
              '${check.distance != null ? ' (L2 ${check.distance!.toStringAsFixed(3)})' : ''}.\n\n'
              'Enroll anyway as "${_nameCtr.text}"?',
              style: GoogleFonts.inter(color: TimoColors.textSecondary),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enroll anyway'),
              ),
            ],
          ),
        );
        if (proceed != true) return; // user cancelled
        if (mounted) setState(() => _enrolling = true);
      }
    }

    final consentRef = 'consent-${DateTime.now().toIso8601String()}';
    int successCount = 0;
    int failureCount = 0;

    // Upload each captured frame (from each pose)
    for (int i = 0; i < widget.capturedFrames.length; i++) {
      try {
        final result = await notifier.enrollOnePhoto(
          fullName: _nameCtr.text,
          role: _roleCtr.text,
          notifyChannel: '',
          consentRef: '$consentRef-pose-$i',
          imageBytes: widget.capturedFrames[i],
          phone: _phoneCtr.text,
          personType: _personType,
        );

        if (result.ok) {
          successCount++;
        } else {
          failureCount++;
          if (mounted) {
            print('Frame $i error: ${result.reason}');
          }
        }
      } catch (err) {
        failureCount++;
        if (mounted) {
          print('Frame $i exception: $err');
        }
      }
    }

    setState(() => _enrolling = false);

    if (mounted) {
      if (successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${_nameCtr.text} enrolled! ($successCount/${widget.capturedFrames.length} poses)'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Enrollment failed ($failureCount poses)'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 500,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: TimoColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enroll Staff Member',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              // Captured frames preview grid
              Text(
                'Captured ${widget.capturedFrames.length} poses:',
                style: GoogleFonts.inter(fontSize: 12, color: TimoColors.textSecondary),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.capturedFrames.length,
                  itemBuilder: (ctx, idx) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      width: 100,
                      decoration: BoxDecoration(
                        border: Border.all(color: TimoColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Stack(
                        children: [
                          Image.memory(
                            widget.capturedFrames[idx],
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            bottom: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                const ['Front', 'Left', 'Right', 'Up', 'Down'][idx],
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Form fields
              TextFormField(
                controller: _nameCtr,
                decoration: InputDecoration(
                  labelText: 'Full Name *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneCtr,
                decoration: InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _personType,
                decoration: InputDecoration(
                  labelText: 'Person Type *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: const [
                  DropdownMenuItem(value: 'Employee', child: Text('Employee')),
                  DropdownMenuItem(value: 'Staff', child: Text('Staff')),
                ]
                    .map((item) => DropdownMenuItem(value: item.value, child: item.child))
                    .toList(),
                onChanged: (v) => setState(() => _personType = v ?? 'Employee'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _roleCtr,
                decoration: InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 24),
              // Consent checkbox
              CheckboxListTile(
                value: _consent,
                onChanged: (v) => setState(() => _consent = v ?? false),
                title: const Text('I consent to enroll my face for identification'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 24),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _consent && _formKey.currentState?.validate() == true && !_enrolling
                          ? _submitEnrollment
                          : null,
                      child: _enrolling
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Enroll'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TimoColors.cardTop,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
