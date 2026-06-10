import 'dart:typed_data';
import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web/web.dart' as web;
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../settings/providers/settings_provider.dart';
import '../../staff/providers/enrollment_provider.dart';
import '../widgets/mjpeg_view.dart';

class LiveFeedScreen extends ConsumerStatefulWidget {
  const LiveFeedScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends ConsumerState<LiveFeedScreen> {
  bool _enrollmentMode = false;
  bool _streaming = false;

  void _toggleEnrollmentMode() {
    setState(() {
      _enrollmentMode = !_enrollmentMode;
    });
  }

  void _onFrameCaptured(Uint8List frame) {
    setState(() => _enrollmentMode = false);
    _showEnrollmentForm(frame);
  }

  void _showEnrollmentForm(Uint8List capturedFrame) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: _EnrollmentFormModal(capturedFrame: capturedFrame),
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
                          _streaming
                              ? MjpegView(url: url)
                              : Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.videocam_off,
                                        size: 64,
                                        color: const Color(0xFF3A3A3A),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: () => setState(() => _streaming = true),
                                        icon: const Icon(Icons.play_arrow),
                                        label: const Text('Start Stream'),
                                      ),
                                    ],
                                  ),
                                ),
                          // Enrollment detection overlay
                          if (_enrollmentMode && _streaming)
                            _EnrollmentDetectionOverlay(
                              mjpegUrl: url,
                              onFrameCaptured: _onFrameCaptured,
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

/// Face detection overlay for enrollment with real face-api detection
class _EnrollmentDetectionOverlay extends StatefulWidget {
  final String mjpegUrl;
  final Function(Uint8List) onFrameCaptured;

  const _EnrollmentDetectionOverlay({
    required this.mjpegUrl,
    required this.onFrameCaptured,
  });

  @override
  State<_EnrollmentDetectionOverlay> createState() => _EnrollmentDetectionOverlayState();
}

class _EnrollmentDetectionOverlayState extends State<_EnrollmentDetectionOverlay> {
  String _status = 'Center your face';
  bool _faceDetected = false;
  bool _modelsLoaded = false;
  Timer? _detectionTimer;
  int _stableFrames = 0;
  static const int _stabilityThreshold = 10; // ~0.5s at 20fps

  @override
  void initState() {
    super.initState();
    _initializeAndDetect();
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeAndDetect() async {
    await _loadFaceApiModels();
    if (!mounted) return;

    // Start continuous detection loop
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) {
        _detectAndCapture();
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

  void _detectAndCapture() {
    if (!_modelsLoaded) return;

    try {
      // Find MJPEG img element (use JS interop since NodeList doesn't support indexing)
      final findImgCode = '''(function() {
        const imgs = document.querySelectorAll('img');
        for (let i = 0; i < imgs.length; i++) {
          if (imgs[i].src && imgs[i].src.includes('${widget.mjpegUrl}')) {
            return imgs[i];
          }
        }
        return null;
      })()''';

      final mjpegImg = js.context.callMethod('eval', [findImgCode]);
      if (mjpegImg == null) return;

      // Run detection via JS interop
      final jsDetectionCode = '''(async function() {
        const img = document.querySelector('img[src*="${widget.mjpegUrl}"]');
        if (!img || img.naturalWidth === 0) return {faces: 0, ready: false};

        try {
          const detections = await faceapi
            .detectAllFaces(img, new faceapi.TinyFaceDetectorOptions())
            .withFaceLandmarks()
            .withFaceDescriptors();

          if (detections.length !== 1) return {faces: detections.length, ready: false};

          const det = detections[0];
          const box = det.box || (det.detection && det.detection.box);
          if (!box) return {faces: 1, ready: false};

          // Check if face is centered and large enough
          const imgW = img.naturalWidth;
          const imgH = img.naturalHeight;
          const facePct = (box.width * box.height) / (imgW * imgH);
          const centerX = (box.x + box.width/2) / imgW;
          const centerY = (box.y + box.height/2) / imgH;

          const isCentered = centerX > 0.3 && centerX < 0.7 && centerY > 0.3 && centerY < 0.7;
          const isLargeEnough = facePct > 0.05;

          return {
            faces: 1,
            ready: isCentered && isLargeEnough,
            box: {x: box.x, y: box.y, width: box.width, height: box.height}
          };
        } catch(e) {
          return {faces: 0, ready: false};
        }
      })()''';

      final jsFunc = js.context.callMethod('eval', [jsDetectionCode]);
      final completer = Completer<Map<String, dynamic>>();

      jsFunc.callMethod('then', [(result) {
        try {
          final resultMap = <String, dynamic>{
            'faces': result['faces'] ?? 0,
            'ready': result['ready'] ?? false,
          };
          completer.complete(resultMap);
        } catch (e) {
          completer.complete({'faces': 0, 'ready': false});
        }
      }]).callMethod('catch', [(err) {
        completer.complete({'faces': 0, 'ready': false});
      }]);

      completer.future.then((result) {
        if (!mounted) return;

        final faces = result['faces'] as int? ?? 0;
        final ready = result['ready'] as bool? ?? false;

        setState(() {
          _faceDetected = ready;
          if (ready) {
            _stableFrames++;
            _status = 'Hold still... ${_stableFrames ~/ 2}s';
          } else {
            _stableFrames = 0;
            if (faces == 0) {
              _status = 'No face detected';
            } else if (faces > 1) {
              _status = 'Only one face allowed';
            } else {
              _status = 'Move closer & center';
            }
          }
        });

        // Auto-capture when stable
        if (ready && _stableFrames >= _stabilityThreshold) {
          _captureFrame();
        }
      });
    } catch (err) {
      print('[EnrollmentDetection] Detection error: $err');
    }
  }

  Future<void> _captureFrame() async {
    _detectionTimer?.cancel();

    try {
      final captureCode = '''(async function() {
        const img = document.querySelector('img[src*="${widget.mjpegUrl}"]');
        if (!img) return null;

        const canvas = document.createElement('canvas');
        canvas.width = img.naturalWidth;
        canvas.height = img.naturalHeight;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0);

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
        // Extract base64 from data URL
        final base64 = dataUrl.split(',').last;
        final bytes = base64Decode(base64);
        if (mounted) {
          widget.onFrameCaptured(bytes);
        }
      }
    } catch (err) {
      print('[EnrollmentDetection] Capture error: $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: _faceDetected ? Colors.green : Colors.orange,
          width: 3,
        ),
      ),
      child: Stack(
        children: [
          // Semi-transparent overlay
          Container(
            color: Colors.black.withOpacity(0.2),
          ),
          // Center hint
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _faceDetected ? Icons.check_circle : Icons.face,
                  size: 80,
                  color: _faceDetected ? Colors.green : Colors.orange,
                ),
                const SizedBox(height: 20),
                Text(
                  _modelsLoaded ? _status : 'Loading face detection...',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_faceDetected && _stableFrames < _stabilityThreshold) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Keep still',
                    style: GoogleFonts.inter(
                      color: Colors.green,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Enrollment form modal with captured frame
class _EnrollmentFormModal extends ConsumerStatefulWidget {
  final Uint8List capturedFrame;

  const _EnrollmentFormModal({required this.capturedFrame});

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
    final consentRef = 'consent-${DateTime.now().toIso8601String()}';

    try {
      final result = await notifier.enrollOnePhoto(
        fullName: _nameCtr.text,
        role: _roleCtr.text,
        notifyChannel: '',
        consentRef: consentRef,
        imageBytes: widget.capturedFrame,
        phone: _phoneCtr.text,
        personType: _personType,
      );

      setState(() => _enrolling = false);

      if (mounted) {
        if (result.ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${_nameCtr.text} enrolled successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${result.reason}')),
          );
        }
      }
    } catch (err) {
      setState(() => _enrolling = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $err')),
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
              // Captured image preview
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: TimoColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.memory(widget.capturedFrame, fit: BoxFit.cover),
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
