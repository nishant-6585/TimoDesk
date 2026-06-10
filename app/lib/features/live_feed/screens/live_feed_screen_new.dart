// New widgets for live feed enrollment - temporary file for reference
// These will be added to the end of live_feed_screen.dart

/// Face detection overlay for enrollment
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
  String _status = 'Detecting face...';
  bool _faceDetected = false;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _faceDetected ? Colors.green : Colors.orange,
            width: 3,
          ),
        ),
        child: Stack(
          children: [
            // Semi-transparent overlay
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.black.withOpacity(0.2),
              ),
            ),
            // Center hint
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _faceDetected ? Icons.check_circle : Icons.face,
                    size: 64,
                    color: _faceDetected ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _faceDetected ? 'Face Detected - Capturing...' : 'Position your face',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
            SnackBar(content: Text('✅ ${_nameCtr.text} enrolled successfully!')),
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
      decoration: BoxDecoration(color: TimoColors.surface, borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enroll Staff Member', style: Theme.of(context).textTheme.titleLarge),
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
              const SizedBox(height: 20),
              // Form fields
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
                ].map((item) => DropdownMenuItem(value: item.value, child: item.child)).toList(),
                onChanged: (v) => setState(() => _personType = v ?? 'Employee'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _roleCtr,
                decoration: const InputDecoration(labelText: 'Role'),
              ),
              const SizedBox(height: 20),
              // Consent
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
              const SizedBox(height: 24),
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _consent && _formKey.currentState?.validate() == true && !_enrolling
                          ? _submitEnrollment
                          : null,
                      child: _enrolling
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Enroll'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: TimoColors.cardTop),
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
