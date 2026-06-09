import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/enrollment_provider.dart';

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
  List<XFile>? _selectedPhotos;
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

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final photos = await picker.pickMultiImage();
    if (photos.isNotEmpty) {
      setState(() {
        _selectedPhotos = photos;
        _photoEnrolled.clear();
        _photoErrors.clear();
        for (int i = 0; i < photos.length; i++) {
          _photoEnrolled.add(false);
          _photoErrors.add(null);
        }
      });
    }
  }

  Future<void> _enrollPhotos() async {
    if (_selectedPhotos == null || _selectedPhotos!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least 1 photo')),
      );
      return;
    }

    final notifier = ref.read(enrollmentProvider.notifier);
    final consentRef = 'consent-${DateTime.now().toIso8601String()}';

    // POST photos SEQUENTIALLY (first creates staff, rest find it)
    for (int i = 0; i < _selectedPhotos!.length; i++) {
      setState(() => _currentPhotoIndex = i);

      try {
        final bytes = await _selectedPhotos![i].readAsBytes();
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
        SnackBar(content: Text('Enrolled ${_photoEnrolled.where((e) => e).length}/${_selectedPhotos!.length} photos')),
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

            // Photo selection
            ElevatedButton.icon(
              icon: const Icon(Icons.image),
              label: const Text('Select Photos (3-5)'),
              onPressed: _pickPhotos,
            ),

            if (_selectedPhotos != null && _selectedPhotos!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('${_selectedPhotos!.length} photos selected'),
              const SizedBox(height: 8),
              // Photo progress
              ..._selectedPhotos!.asMap().entries.map((e) {
                final idx = e.key;
                final photo = e.value;
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
                        child: Image.network(photo.path, fit: BoxFit.cover),
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
                              Text('❌ $error', style: const TextStyle(color: Colors.red))
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
                onPressed: (_consent && _selectedPhotos != null && _selectedPhotos!.isNotEmpty)
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
