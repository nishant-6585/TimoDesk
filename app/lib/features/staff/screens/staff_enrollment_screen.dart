import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../providers/enrollment_provider.dart';

/// Staff enrollment — captures the employee's front-facing photo live from the
/// webcam, collects their details, then enrols. Face detection happens server-side
/// in spine (/enroll requires exactly one face), so no client-side ML is needed —
/// which is what lets this run in the browser (ML Kit is mobile-only).
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

  CameraController? _camera;
  bool _cameraReady = false;
  String? _cameraError;

  Uint8List? _captured; // The single front-facing shot
  bool _enrolling = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _camera?.dispose();
    _nameCtr.dispose();
    _phoneCtr.dispose();
    _roleCtr.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera found on this device.');
        return;
      }
      // Prefer the user-facing (front) camera for a selfie-style enrolment shot.
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(front, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _camera = controller;
        _cameraReady = true;
      });
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera access failed: $e');
    }
  }

  Future<void> _capture() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized || cam.value.isTakingPicture) return;
    try {
      final file = await cam.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _captured = bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Capture failed: $e')));
      }
    }
  }

  void _retake() => setState(() => _captured = null);

  Future<void> _submitEnrollment() async {
    if (_captured == null) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_consent) return;

    setState(() => _enrolling = true);

    final notifier = ref.read(enrollmentProvider.notifier);
    final consentRef = 'consent-${DateTime.now().toIso8601String()}';

    String? error;
    try {
      final result = await notifier.enrollOnePhoto(
        fullName: _nameCtr.text,
        role: _roleCtr.text,
        notifyChannel: '',
        consentRef: consentRef,
        imageBytes: _captured!,
        phone: _phoneCtr.text,
        personType: _personType,
        setThumbnail: true, // This is the front shot → it becomes the gallery image.
      );
      if (!result.ok) {
        error = result.reason ?? 'Enrollment failed';
        if (result.facesFound != null && result.facesFound != 1) {
          error = result.facesFound == 0
              ? 'No face detected — re-take with your face centered and well-lit.'
              : 'Multiple faces detected — only the employee should be in frame.';
        }
      }
    } catch (err) {
      error = err.toString();
    }

    if (!mounted) return;
    setState(() => _enrolling = false);

    if (error == null) {
      // Close the details sheet, then leave the screen.
      Navigator.pop(context); // sheet
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_nameCtr.text} enrolled successfully'), backgroundColor: Colors.green.shade800),
      );
      Navigator.pop(context); // screen
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _showDetailsForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: MikeeColors.surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
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
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneCtr,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _personType,
                  decoration: const InputDecoration(labelText: 'Person Type *'),
                  items: const [
                    DropdownMenuItem(value: 'Employee', child: Text('Employee')),
                    DropdownMenuItem(value: 'Staff', child: Text('Staff')),
                  ],
                  onChanged: (v) => setSheetState(() => _personType = v ?? 'Employee'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _roleCtr,
                  decoration: const InputDecoration(labelText: 'Role'),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Checkbox(
                      value: _consent,
                      onChanged: (v) => setSheetState(() => _consent = v ?? false),
                    ),
                    const Expanded(
                      child: Text('I consent to enroll my face for identification'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_consent && !_enrolling) ? _submitEnrollment : null,
                        child: _enrolling
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Enroll'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: MikeeColors.cardTop),
                        onPressed: _enrolling ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MikeeColors.background,
      appBar: AppBar(title: const Text('Enroll Staff')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _captured != null ? _buildReview() : _buildCamera(),
          ),
        ),
      ),
    );
  }

  Widget _buildCamera() {
    if (_cameraError != null) {
      return _Message(
        icon: Icons.videocam_off_rounded,
        title: 'Camera unavailable',
        detail: '$_cameraError\n\nAllow camera access in your browser and reload.',
        action: ('Retry', () { setState(() => _cameraError = null); _initCamera(); }),
      );
    }
    if (!_cameraReady || _camera == null) {
      return const _Message(
        icon: Icons.videocam_rounded,
        title: 'Starting camera…',
        detail: 'Allow camera access if your browser prompts.',
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: _camera!.value.aspectRatio,
            child: CameraPreview(_camera!),
          ),
        ),
        const SizedBox(height: 16),
        Text('Center the employee’s face, look straight ahead.',
            style: TextStyle(color: MikeeColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _capture,
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Capture Photo'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReview() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(_captured!, height: 380, fit: BoxFit.contain),
        ),
        const SizedBox(height: 16),
        Text('Use this photo? It will be saved as the gallery image.',
            style: TextStyle(color: MikeeColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _retake,
              icon: const Icon(Icons.refresh_rounded),
              label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Retake')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _showDetailsForm,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Enter Details')),
            ),
          ),
        ]),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final (String, VoidCallback)? action;
  const _Message({required this.icon, required this.title, required this.detail, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: MikeeColors.textMuted),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(detail, textAlign: TextAlign.center, style: TextStyle(color: MikeeColors.textSecondary, fontSize: 13)),
          if (action != null) ...[
            const SizedBox(height: 20),
            ElevatedButton(onPressed: action!.$2, child: Text(action!.$1)),
          ],
        ],
      ),
    );
  }
}
