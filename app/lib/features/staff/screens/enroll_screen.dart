import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/enrollment_provider.dart';
import 'camera_capture_screen.dart';

class EnrollmentScreen extends ConsumerStatefulWidget {
  const EnrollmentScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends ConsumerState<EnrollmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtr = TextEditingController();
  final _roleCtr = TextEditingController();
  final _channelCtr = TextEditingController();
  bool _consent = false;
  List<Uint8List>? _capturedFrames; // From camera or picker
  int _currentPhotoIndex = 0;
  final List<bool> _photoEnrolled = [];
  final List<String?> _photoErrors = [];

  @override
  void dispose() {
    _nameCtr.dispose();
    _roleCtr.dispose();
    _channelCtr.dispose();
    super.dispose();
  }

  Future<void> _launchCapture() async {
    if (!_formKey.currentState!.validate() || !_consent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill form and check consent first')),
      );
      return;
    }

    // Mobile: use camera capture
    if (!kIsWeb) {
      final frames = await Navigator.of(context).push<List<Uint8List>>(
        MaterialPageRoute(
          builder: (context) => CameraCaptureScreen(
            fullName: _nameCtr.text,
            role: _roleCtr.text,
            notifyChannel: _channelCtr.text,
            onFramesCapture: (frames) {
              // This callback is used internally by camera screen
            },
          ),
        ),
      );

      if (frames != null && frames.isNotEmpty) {
        _prepareFrames(frames);
      }
    } else {
      // Web: use image_picker (ML Kit not available)
      final picker = ImagePicker();
      final photos = await picker.pickMultiImage();
      if (photos.isNotEmpty) {
        final frames = await Future.wait(photos.map((p) => p.readAsBytes()));
        _prepareFrames(frames);
      }
    }
  }

  void _prepareFrames(List<Uint8List> frames) {
    setState(() {
      _capturedFrames = frames;
      _photoEnrolled.clear();
      _photoErrors.clear();
      for (int i = 0; i < frames.length; i++) {
        _photoEnrolled.add(false);
        _photoErrors.add(null);
      }
    });
  }

  Future<void> _enrollPhotos() async {
    if (_capturedFrames == null || _capturedFrames!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture at least 1 photo')),
      );
      return;
    }

    final notifier = ref.read(enrollmentProvider.notifier);
    final consentRef = 'consent-${DateTime.now().toIso8601String()}';

    // POST frames SEQUENTIALLY (first creates staff, rest find it)
    for (int i = 0; i < _capturedFrames!.length; i++) {
      setState(() => _currentPhotoIndex = i);

      try {
        final bytes = _capturedFrames![i];
        final result = await notifier.enrollOnePhoto(
          fullName: _nameCtr.text,
          role: _roleCtr.text,
          notifyChannel: _channelCtr.text,
          consentRef: '$consentRef-photo-$i',
          imageBytes: bytes,
        );

        setState(() {
          if (result.ok) {
            _photoEnrolled[i] = true;
            _photoErrors[i] = null;
          } else {
            _photoErrors[i] = result.reason ?? 'Unknown error (facesFound: ${result.facesFound})';
          }
        });
      } catch (err) {
        setState(() {
          _photoErrors[i] = err.toString();
        });
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enrolled ${_photoEnrolled.where((e) => e).length}/${_capturedFrames!.length} photos')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enroll Staff')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Form
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameCtr,
                    decoration: const InputDecoration(labelText: 'Full Name'),
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _roleCtr,
                    decoration: const InputDecoration(labelText: 'Role'),
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _channelCtr,
                    decoration: const InputDecoration(labelText: 'Notify Channel'),
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                  ),
                  const SizedBox(height: 24),
                  // Consent checkbox (MANDATORY)
                  Row(
                    children: [
                      Checkbox(
                        value: _consent,
                        onChanged: (v) => setState(() => _consent = v ?? false),
                      ),
                      const Expanded(
                        child: Text('I consent to enroll my face for identification'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Capture button (mobile: auto-capture with face detection, web: manual picker)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(kIsWeb ? Icons.image : Icons.camera),
                label: Text(kIsWeb ? 'Select Photos' : 'Auto-Capture (Face Detection)'),
                onPressed: _launchCapture,
              ),
            ),

            if (_capturedFrames != null && _capturedFrames!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('${_capturedFrames!.length} photos captured'),
              const SizedBox(height: 8),
              // Photo progress
              ..._capturedFrames!.asMap().entries.map((e) {
                final idx = e.key;
                final frame = e.value;
                final enrolled = _photoEnrolled[idx];
                final error = _photoErrors[idx];

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Image.memory(frame, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Photo ${idx + 1}'),
                            if (enrolled)
                              const Text('✅ Enrolled', style: TextStyle(color: Colors.green))
                            else if (error != null)
                              Text('❌ ${error.length > 50 ? error.substring(0, 50) + '...' : error}',
                                  style: const TextStyle(color: Colors.red), overflow: TextOverflow.ellipsis)
                            else if (_currentPhotoIndex == idx)
                              const Text('⏳ Uploading...', style: TextStyle(color: Colors.orange))
                            else
                              const Text('⏳ Pending'),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],

            const SizedBox(height: 24),

            // Enroll button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_consent && _capturedFrames != null && _capturedFrames!.isNotEmpty)
                    ? _enrollPhotos
                    : null,
                child: const Text('Enroll Staff'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
