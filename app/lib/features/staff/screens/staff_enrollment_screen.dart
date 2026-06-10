import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme.dart';
import '../models/staff_enroll_model.dart';
import '../providers/enrollment_provider.dart';
import '../../live_feed/widgets/mjpeg_view.dart';

/// Staff enrollment: live detection + auto-capture + details form + duplicate check
class StaffEnrollmentScreen extends ConsumerStatefulWidget {
  const StaffEnrollmentScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<StaffEnrollmentScreen> createState() => _StaffEnrollmentScreenState();
}

class _StaffEnrollmentScreenState extends ConsumerState<StaffEnrollmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtr = TextEditingController();
  final _phoneCtr = TextEditingController();
  final _roleCtr = TextEditingController();
  String _personType = 'Employee';
  bool _consent = false;

  List<Uint8List>? _capturedFrames;
  bool _enrolling = false;
  String? _duplicateWarning;
  int _currentPhotoIndex = 0;
  final List<bool> _photoEnrolled = [];
  final List<String?> _photoErrors = [];

  @override
  void dispose() {
    _nameCtr.dispose();
    _phoneCtr.dispose();
    _roleCtr.dispose();
    super.dispose();
  }

  Future<void> _handleFrameCapture(List<Uint8List> frames) async {
    setState(() {
      _capturedFrames = frames;
      _photoEnrolled.clear();
      _photoErrors.clear();
      for (int i = 0; i < frames.length; i++) {
        _photoEnrolled.add(false);
        _photoErrors.add(null);
      }
    });

    // Show form for captured frames
    _showDetailsForm();
  }

  Future<void> _uploadManualPhotos() async {
    final picker = ImagePicker();
    final photos = await picker.pickMultiImage();
    if (photos.isNotEmpty) {
      final frames = await Future.wait(photos.map((p) => p.readAsBytes()));
      _handleFrameCapture(frames);
    }
  }

  void _showDetailsForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: TimoColors.surface,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Staff Enrollment Details', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtr,
                decoration: const InputDecoration(labelText: 'Full Name *'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneCtr,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _personType,
                decoration: const InputDecoration(labelText: 'Person Type *'),
                items: const [
                  DropdownMenuItem(value: 'Employee', child: Text('Employee')),
                  DropdownMenuItem(value: 'Staff', child: Text('Staff')),
                ]
                    .map((item) => DropdownMenuItem(
                          value: item.value,
                          child: item.child,
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _personType = v ?? 'Employee'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _roleCtr,
                decoration: const InputDecoration(labelText: 'Role'),
              ),
              const SizedBox(height: 20),
              // Consent checkbox
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
              // Duplicate warning
              if (_duplicateWarning != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    border: Border.all(color: Colors.orange),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _duplicateWarning!,
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _consent && _formKey.currentState!.validate() ? _submitEnrollment : null,
                      child: const Text('Enroll'),
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

  Future<void> _submitEnrollment() async {
    if (_capturedFrames == null || _capturedFrames!.isEmpty) return;

    if (!_formKey.currentState!.validate()) return;

    setState(() => _enrolling = true);

    final notifier = ref.read(enrollmentProvider.notifier);
    final consentRef = 'consent-${DateTime.now().toIso8601String()}';

    for (int i = 0; i < _capturedFrames!.length; i++) {
      setState(() => _currentPhotoIndex = i);

      try {
        final result = await notifier.enrollOnePhoto(
          fullName: _nameCtr.text,
          role: _roleCtr.text,
          notifyChannel: '', // Not used for staff enrollment
          consentRef: '$consentRef-photo-$i',
          imageBytes: _capturedFrames![i],
          phone: _phoneCtr.text,
          personType: _personType,
        );

        setState(() {
          if (result.ok) {
            _photoEnrolled[i] = true;
            _photoErrors[i] = null;
          } else {
            _photoErrors[i] = result.reason ?? 'Enrollment failed';
          }
        });
      } catch (err) {
        setState(() {
          _photoErrors[i] = err.toString();
        });
      }
    }

    setState(() => _enrolling = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Enrolled ${_photoEnrolled.where((e) => e).length}/${_capturedFrames!.length} photos'),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TimoColors.background,
      appBar: AppBar(
        title: const Text('Enroll Staff'),
      ),
      body: Column(
        children: [
          // Live feed with detection overlay
          Expanded(
            child: StaffEnrollmentLiveView(
              onFramesCaptured: _handleFrameCapture,
            ),
          ),
        ],
      ),
    );
  }
}

/// Live detection view with overlay + auto-capture
class StaffEnrollmentLiveView extends StatefulWidget {
  final Function(List<Uint8List>) onFramesCaptured;

  const StaffEnrollmentLiveView({
    Key? key,
    required this.onFramesCaptured,
  }) : super(key: key);

  @override
  State<StaffEnrollmentLiveView> createState() => _StaffEnrollmentLiveViewState();
}

class _StaffEnrollmentLiveViewState extends State<StaffEnrollmentLiveView> {
  @override
  Widget build(BuildContext context) {
    // TODO: Integrate live detection overlay with color-coded box
    // For now, show the MJPEG feed (Milestone A verified)
    // Next iteration adds the overlay canvas + detection state machine

    return Stack(
      children: [
        // Live MJPEG feed from robot
        Scaffold(
          body: buildMjpegView(
            context,
            'http://192.168.10.18:8080/stream',
            BoxFit.cover,
          ),
        ),
        // TODO: Overlay canvas for face detection box
        // TODO: State machine for color (none/red → orange → green)
        // TODO: Auto-capture trigger on green gate

        // Manual upload button (for testing backend path)
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton(
            onPressed: _uploadManualPhotos,
            tooltip: 'Upload photos manually',
            child: const Icon(Icons.image),
          ),
        ),
      ],
    );
  }
}
