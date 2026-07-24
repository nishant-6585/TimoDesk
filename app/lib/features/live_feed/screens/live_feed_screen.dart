import 'dart:typed_data';
import 'dart:async';
import 'dart:convert' show base64Decode, jsonEncode, jsonDecode;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants.dart';
import '../../../core/spine_base.dart';
import '../../../core/theme.dart';
import '../../../services/spine/visitor_arrived_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../services/spine/spine_provider.dart';
import '../../staff/providers/enrollment_provider.dart';
import '../../staff/providers/staff_list_provider.dart';
import '../../staff/screens/staff_list_screen.dart';
import '../widgets/mjpeg_view.dart';
import '../widgets/enroll_webcam_view.dart';
import '../widgets/web_face_api.dart';

/// Where enrollment reads frames from.
enum _EnrollSource { device, robot }

class LiveFeedScreen extends ConsumerStatefulWidget {
  const LiveFeedScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends ConsumerState<LiveFeedScreen> {
  bool _enrollmentMode = false;
  bool _streaming = true; // auto-start: the feed is the point of the panel
  // Default to this device's webcam in the browser so the person, the camera,
  // and the on-screen guidance are all in one place.
  _EnrollSource _enrollSource = _EnrollSource.device;

  void _toggleEnrollmentMode() {
    // Face-api + webcam enrollment is web-only (runs in the browser). On native
    // the compile seam stays safe; this guard keeps the UI graceful at runtime.
    if (!kIsWeb && !_enrollmentMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Face enrollment runs in the web app. On a device, enroll from the robot chest screen.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _enrollmentMode = !_enrollmentMode;
      // Robot-source enrollment needs the MJPEG running; device-source uses the
      // webcam which starts itself.
      if (_enrollmentMode && _enrollSource == _EnrollSource.robot) _streaming = true;
    });
  }

  // The detection overlay should run once the chosen source is showing frames.
  // Web-only (face-api) — never active on native.
  bool get _overlayActive {
    if (!kIsWeb || !_enrollmentMode) return false;
    return _enrollSource == _EnrollSource.device || _streaming;
  }

  // Which media element fills the camera box right now.
  Widget _buildCameraLayer(String url) {
    if (_enrollmentMode && _enrollSource == _EnrollSource.device) {
      return const DeviceWebcamView();
    }
    // Enrollment over the robot stream reads frames back for face-api, so it
    // needs crossOrigin; plain viewing must not set it (breaks MJPEG render).
    if (_streaming) return MjpegView(url: url, crossOrigin: _enrollmentMode && _enrollSource == _EnrollSource.robot);
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

  /// Called after the first pose. Returns true to keep capturing, false to abort.
  /// If the face matches an enrolled person, asks the user whether to continue.
  Future<bool> _checkDuplicateDuringCapture(Uint8List firstFrame) async {
    final check = await ref.read(enrollmentProvider.notifier).checkFace(firstFrame);
    if (!check.match || !mounted) return true; // new face → keep going

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MikeeColors.surface,
        title: const Text('Already enrolled'),
        content: Text(
          'This face looks like ${check.name} is already enrolled'
          '${check.distance != null ? ' (L2 ${check.distance!.toStringAsFixed(3)})' : ''}.\n\n'
          'Stop, or continue enrolling anyway?',
          style: GoogleFonts.inter(color: MikeeColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stop')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue anyway'),
          ),
        ],
      ),
    );
    return proceed == true;
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
      backgroundColor: MikeeColors.background,
      body: Column(
        children: [
          // Local action bar — the AppShell's top status bar stays above this.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Row(
              children: [
                Text('Enrol Staff', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary)),
                const Spacer(),
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
              ],
            ),
          ),
          // Live visitor-arrival banner (driven by visitorArrivedProvider).
          const _VisitorArrivalBanner(),
          Expanded(
            child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 700),
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: MikeeColors.border),
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
                                  color: _streaming ? MikeeColors.error : MikeeColors.textMuted,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _streaming ? 'LIVE' : 'OFFLINE',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _streaming ? MikeeColors.error : MikeeColors.textMuted,
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
                                color: _streaming ? MikeeColors.error : MikeeColors.primary,
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
                              onCheckDuplicate: _checkDuplicateDuringCapture,
                              onAbort: () => setState(() => _enrollmentMode = false),
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
          ),
          // Visitor self-check-in → notify host (#70).
          const _VisitorCheckInCard(),
        ],
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
            color: active ? MikeeColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: active ? Colors.white : MikeeColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : MikeeColors.textSecondary,
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
        border: Border.all(color: MikeeColors.border),
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
  // Called after the FIRST pose is captured with that frontal frame. Returns
  // true to continue the pose flow, false to abort (already-enrolled, cancelled).
  final Future<bool> Function(Uint8List firstFrame)? onCheckDuplicate;
  // Called when the flow is aborted (e.g. duplicate, user cancelled).
  final VoidCallback? onAbort;

  const _EnrollmentDetectionOverlay({
    required this.elementSelector,
    required this.onFramesCaptured,
    this.onCheckDuplicate,
    this.onAbort,
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
      const modelUrl = 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@latest/model/';
      final ok = await faceApiLoadModels(modelUrl);
      if (ok && mounted) {
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

    // Detect 1 face + landmarks; compute size, centering, yaw and a pitch proxy.
    // Works for both <img> (MJPEG) and <video> (webcam). The dart:js detail lives
    // behind the web_face_api seam — this screen stays native-compilable.
    faceApiDetect(widget.elementSelector).then((r) {
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
    }).catchError((err) {
      print('[EnrollmentDetection] Detection error: $err');
    });
  }

  Future<void> _captureFrame() async {
    // Enter captured phase immediately so the detection loop stops trying to capture.
    setState(() {
      _phase = 'captured';
      _stableFrames = 0;
    });

    try {
      final dataUrl = await faceApiCapture(widget.elementSelector);
      if (dataUrl != null && dataUrl.isNotEmpty) {
        final base64 = dataUrl.split(',').last;
        final bytes = base64Decode(base64);

        if (mounted) {
          setState(() {
            _capturedFrames.add(bytes);
            _status = '✓ Captured ${_currentPose.name}';
            _faceDetected = true;
          });

          // Duplicate guard right after the FIRST (frontal) pose — catch an
          // already-enrolled person before they do all 5 poses.
          if (_currentPoseIndex == 0 && widget.onCheckDuplicate != null) {
            setState(() {
              _phase = 'checking';
              _status = 'Checking if already enrolled…';
            });
            final proceed = await widget.onCheckDuplicate!(bytes);
            if (!mounted) return;
            if (!proceed) {
              _detectionTimer?.cancel();
              _getReadyTimer?.cancel();
              widget.onAbort?.call();
              return;
            }
            _advanceOrFinish(); // check passed — continue immediately
            return;
          }

          // Brief confirmation pause, then get-ready for the next pose.
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (mounted) _advanceOrFinish();
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

  // Move to the next pose, or finish and hand frames back.
  void _advanceOrFinish() {
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
              style: GoogleFonts.inter(color: MikeeColors.primary, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1)),
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

    // Checking duplicate after the first pose.
    if (_phase == 'checking') {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 56, height: 56, child: CircularProgressIndicator()),
          const SizedBox(height: 18),
          Text('Checking if already enrolled…',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
  // Optional desk/location pose captured from the robot's current SLAM position,
  // saved with the staff row so Timo can later navigate to this person's desk (#71).
  Map<String, double>? _deskPose;
  bool _capturingDesk = false;

  @override
  void dispose() {
    _nameCtr.dispose();
    _phoneCtr.dispose();
    _roleCtr.dispose();
    super.dispose();
  }

  /// Capture the robot's live SLAM pose as this person's desk location. The robot
  /// must be parked at the desk (drive it there first). Optional — skip to enroll
  /// without a location.
  Future<void> _captureDesk() async {
    setState(() => _capturingDesk = true);
    try {
      final pose = await ref.read(spineProvider.notifier).getPosition();
      if (!mounted) return;
      if (pose == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not read robot position (offline or timed out)'),
          backgroundColor: Colors.red,
        ));
      } else {
        setState(() => _deskPose = pose);
      }
    } finally {
      if (mounted) setState(() => _capturingDesk = false);
    }
  }

  Future<void> _submitEnrollment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enrolling = true);

    final notifier = ref.read(enrollmentProvider.notifier);
    // (Duplicate detection runs live during pose capture, not here.)
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
          deskPose: i == 0 ? _deskPose : null, // send once; spine writes it to the staff row
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
        color: MikeeColors.surface,
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
                style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textSecondary),
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
                        border: Border.all(color: MikeeColors.border),
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
              const SizedBox(height: 16),
              // Desk location (optional) — capture the robot's current SLAM pose so
              // Timo can navigate to this person's desk later. Park the robot at the
              // desk first. Skip to enroll without a location.
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: MikeeColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  Icon(
                    _deskPose != null ? Icons.place : Icons.place_outlined,
                    size: 20,
                    color: _deskPose != null ? MikeeColors.success : MikeeColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Desk location (optional)',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(
                          _deskPose != null
                              ? 'Captured: x=${_deskPose!['x']!.toStringAsFixed(2)}, y=${_deskPose!['y']!.toStringAsFixed(2)}'
                              : 'Park the robot at the desk, then capture.',
                          style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (_deskPose != null)
                    IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _capturingDesk ? null : () => setState(() => _deskPose = null),
                    ),
                  TextButton.icon(
                    onPressed: _capturingDesk ? null : _captureDesk,
                    icon: _capturingDesk
                        ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, size: 16),
                    label: Text(_deskPose != null ? 'Recapture' : 'Capture'),
                  ),
                ]),
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
                        backgroundColor: MikeeColors.cardTop,
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

/// Visitor self-check-in card — "who are you here to see?" → POST /visit.
class _VisitorCheckInCard extends ConsumerStatefulWidget {
  const _VisitorCheckInCard();
  @override
  ConsumerState<_VisitorCheckInCard> createState() => _VisitorCheckInCardState();
}

class _VisitorCheckInCardState extends ConsumerState<_VisitorCheckInCard> {
  final _nameCtr = TextEditingController();
  String? _hostId;
  bool _sending = false;

  @override
  void dispose() {
    _nameCtr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtr.text.trim();
    if (name.isEmpty || _hostId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your name and pick who you are visiting')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final token = Supabase.instance.client.auth.currentSession?.accessToken ?? 'test-token';
      final res = await http
          .post(
            Uri.parse('$spineHttpBase/visit'),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            body: jsonEncode({'visitor_name': name, 'host_staff_id': _hostId}),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        final hostName = (data['host']?['full_name'] as String?) ?? 'the host';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notification sent to $hostName'), backgroundColor: Colors.green),
        );
        setState(() {
          _nameCtr.clear();
          _hostId = null;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check-in failed: ${data['reason'] ?? 'unknown error'}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Check-in error: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffListProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: MikeeColors.surface,
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.how_to_reg, color: MikeeColors.primary),
          title: Text('Visitor check-in',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          subtitle: Text('Who are you here to see?',
              style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textSecondary)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            TextField(
              controller: _nameCtr,
              decoration: InputDecoration(
                labelText: 'Your name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            staffAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Could not load staff: $e',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              data: (staff) => DropdownButtonFormField<String>(
                value: _hostId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Host (who you are visiting)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: staff
                    .map((s) => DropdownMenuItem(value: s.id, child: Text(s.fullName)))
                    .toList(),
                onChanged: (v) => setState(() => _hostId = v),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _submit,
                icon: _sending
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.notifications_active),
                label: Text(_sending ? 'Sending…' : 'Notify host'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dismissible banner shown when a visitor_arrived event arrives over the WS.
class _VisitorArrivalBanner extends ConsumerWidget {
  const _VisitorArrivalBanner();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(visitorArrivedProvider);
    if (v == null) return const SizedBox.shrink();
    return Material(
      color: MikeeColors.primary.withOpacity(0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.how_to_reg, color: MikeeColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '👋 ${v.visitorName} is here to see ${v.hostName} · notified via ${v.channel}',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: MikeeColors.textPrimary),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => ref.read(visitorArrivedProvider.notifier).clear(),
            ),
          ],
        ),
      ),
    );
  }
}
