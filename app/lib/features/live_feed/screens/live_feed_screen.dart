import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/spine/spine_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../staff/providers/enrollment_provider.dart';
import '../widgets/mjpeg_view.dart';
import '../widgets/face_detection_test.dart';

class LiveFeedScreen extends ConsumerStatefulWidget {
  const LiveFeedScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends ConsumerState<LiveFeedScreen> {
  bool _isRecording = false;
  String _resolution = '640x480';
  String _quality = 'High';
  bool _enrollmentMode = false;
  Uint8List? _capturedFrame;

  void _takeSnapshot() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [Icon(Icons.check_circle, color: TimoColors.success, size: 20), const SizedBox(width: 12), Text('Snapshot saved', style: GoogleFonts.inter(fontSize: 13))]),
        backgroundColor: TimoColors.cardTop,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleRecord() {
    setState(() => _isRecording = !_isRecording);
  }

  void _openFaceDetectionTest() {
    final settings = ref.read(settingsProvider);
    final url = 'http://${settings.robotIp}:8080/stream'; // Camera port always 8080

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: FaceDetectionTest(mjpegUrl: url),
      ),
    );
  }

  void _toggleEnrollmentMode() {
    setState(() {
      _enrollmentMode = !_enrollmentMode;
      if (!_enrollmentMode) {
        _capturedFrame = null;
      }
    });
  }

  void _onFrameCaptured(Uint8List frame) {
    setState(() {
      _capturedFrame = frame;
      _enrollmentMode = false; // Exit detection mode
    });
    // Show enrollment form with captured frame
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
    final compact = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: TimoColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              // Header
              Container(
                height: 64,
                decoration: BoxDecoration(color: TimoColors.surface.withOpacity(0.8), border: const Border(bottom: BorderSide(color: TimoColors.border))),
                padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Row(children: [
                    Container(width: 36, height: 36, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [TimoColors.primary, TimoColors.primaryDark]), boxShadow: [BoxShadow(color: TimoColors.primary.withOpacity(0.35), blurRadius: 16)]), child: Center(child: Text('X', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)))),
                    if (!compact) ...[const SizedBox(width: 12), Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('TimoDesk', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: TimoColors.textPrimary, height: 1.0)), Text('xboom', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.15, color: TimoColors.textMuted, height: 1.0))])]
                  ]),
                  if (!compact) Text('Live Feed', style: GoogleFonts.inter(fontSize: 13, color: TimoColors.textSecondary)),
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: TimoColors.success.withOpacity(0.08), border: Border.all(color: TimoColors.success.withOpacity(0.3)), borderRadius: BorderRadius.circular(8)), child: Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: TimoColors.success)), const SizedBox(width: 8), Text('ONLINE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: TimoColors.success))])),
                    const SizedBox(width: 12),
                    Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: TimoColors.border, width: 2), color: const Color(0xFF2A2A2A)), child: Center(child: Text('NK', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)))),
                  ]),
                ]),
              ),
              // Sidebar + Content
              Expanded(
                child: Row(
                  children: [
                    if (!compact) _Sidebar(onNav: (route) {
                      final routes = {'dashboard': '/', 'control': '/control', 'feed': '/live-feed', 'gallery': '/gallery', 'events': '/event-log', 'settings': '/settings'};
                      if (routes.containsKey(route)) context.go(routes[route]!);
                    }),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1240),
                            child: Column(children: [
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [Icon(Icons.videocam, size: 28, color: TimoColors.primary), const SizedBox(width: 12), Text('Live Feed', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold))]),
                                  const SizedBox(height: 4),
                                  Text('Camera stream · ${ref.watch(settingsProvider).robotIp}:$robotCameraPort', style: GoogleFonts.inter(fontSize: 13, color: TimoColors.textSecondary)),
                                ]),
                                Row(children: [
                                  TextButton.icon(onPressed: _takeSnapshot, icon: const Icon(Icons.photo_camera, size: 20), label: Text('Snapshot', style: GoogleFonts.inter(fontSize: 13))),
                                  const SizedBox(width: 12),
                                  TextButton.icon(
                                    onPressed: _openFaceDetectionTest,
                                    icon: const Icon(Icons.face, size: 20),
                                    label: Text('Face Test', style: GoogleFonts.inter(fontSize: 13)),
                                  ),
                                  const SizedBox(width: 12),
                                  TextButton.icon(
                                    onPressed: _toggleEnrollmentMode,
                                    icon: const Icon(Icons.person_add, size: 20),
                                    label: Text(_enrollmentMode ? 'Cancel Enroll' : 'Enroll Staff', style: GoogleFonts.inter(fontSize: 13)),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: _toggleRecord,
                                    style: ElevatedButton.styleFrom(backgroundColor: _isRecording ? const Color(0xFFEF4444) : TimoColors.cardTop, foregroundColor: Colors.white, side: BorderSide(color: _isRecording ? const Color(0xFFEF4444) : TimoColors.border)),
                                    child: Text(_isRecording ? 'Stop Rec' : 'Record', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                                  ),
                                ]),
                              ]),
                              const SizedBox(height: 20),
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(
                                  flex: 3,
                                  child: _LiveFeedCard(
                                    enrollmentMode: _enrollmentMode,
                                    onFrameCaptured: _onFrameCaptured,
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(flex: 1, child: Column(children: [
                                  _CameraCard(resolution: _resolution, quality: _quality, onResolutionChange: (v) => setState(() => _resolution = v), onQualityChange: (v) => setState(() => _quality = v)),
                                  const SizedBox(height: 20),
                                  _StreamStatsCard(),
                                ])),
                              ]),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final Function(String) onNav;
  const _Sidebar({required this.onNav});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(color: TimoColors.surface, border: const Border(right: BorderSide(color: TimoColors.border))),
      child: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [
          _NavItem('Dashboard', Icons.space_dashboard, false, () => onNav('dashboard')),
          _NavItem('Control', Icons.sports_esports, false, () => onNav('control')),
          _NavItem('Live Feed', Icons.videocam, true, () => onNav('feed')),
          _NavItem('Gallery', Icons.photo_library, false, () => onNav('gallery')),
          _NavItem('Event Log', Icons.receipt_long, false, () => onNav('events')),
          _NavItem('Settings', Icons.settings, false, () => onNav('settings')),
        ])),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _NavItem(this.label, this.icon, this.active, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: active ? TimoColors.primary.withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          if (active) Container(width: 4, height: 20, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: TimoColors.primary, borderRadius: BorderRadius.circular(999))),
          Icon(icon, size: 20, color: active ? TimoColors.primary : TimoColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: active ? FontWeight.w500 : FontWeight.normal, color: active ? TimoColors.primary : TimoColors.textSecondary))),
        ]),
      ))),
    );
  }
}

class _LiveFeedCard extends ConsumerStatefulWidget {
  final bool enrollmentMode;
  final Function(Uint8List) onFrameCaptured;

  const _LiveFeedCard({
    required this.enrollmentMode,
    required this.onFrameCaptured,
  });

  @override
  ConsumerState<_LiveFeedCard> createState() => _LiveFeedCardState();
}

class _LiveFeedCardState extends ConsumerState<_LiveFeedCard> {
  bool _streaming = false;

  @override
  Widget build(BuildContext context) {
    final robotIp = ref.watch(settingsProvider).robotIp;
    final url = robotStreamUrl(robotIp);

    return Container(
      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _streaming ? TimoColors.error : TimoColors.textMuted)), const SizedBox(width: 8), Text(_streaming ? 'LIVE' : 'OFFLINE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _streaming ? TimoColors.error : TimoColors.textMuted, letterSpacing: 0.1))]),
            InkWell(
              onTap: () => setState(() => _streaming = !_streaming),
              borderRadius: BorderRadius.circular(8),
              child: Padding(padding: const EdgeInsets.all(4), child: Icon(_streaming ? Icons.stop_circle_outlined : Icons.play_circle_outline, size: 22, color: _streaming ? TimoColors.error : TimoColors.primary)),
            ),
          ]),
        ),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            children: [
              _streaming
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: MjpegView(url: url),
                    )
                  : _StreamPlaceholder(onStart: () => setState(() => _streaming = true)),
              // Enrollment detection overlay
              if (widget.enrollmentMode && _streaming)
                _EnrollmentDetectionOverlay(
                  mjpegUrl: url,
                  onFrameCaptured: widget.onFrameCaptured,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [Text('Live Feed · $robotIp:$robotCameraPort', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: TimoColors.textSecondary)), const SizedBox(height: 12), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('RES 640×480', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: TimoColors.textMuted)), Text(_streaming ? 'MJPEG' : 'IDLE', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: _streaming ? TimoColors.success : TimoColors.textMuted)), Text('PORT $robotCameraPort', style: GoogleFonts.jetBrainsMono(fontSize: 10))])]),
        ),
      ]),
    );
  }
}

class _StreamPlaceholder extends StatelessWidget {
  final VoidCallback onStart;
  const _StreamPlaceholder({required this.onStart});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.videocam_off, size: 56, color: const Color(0xFF3A3A3A)),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: Text('Start stream', style: GoogleFonts.inter(fontSize: 13)),
        ),
      ]),
    );
  }
}

class _CameraCard extends StatelessWidget {
  final String resolution, quality;
  final Function(String) onResolutionChange, onQualityChange;
  const _CameraCard({required this.resolution, required this.quality, required this.onResolutionChange, required this.onQualityChange});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [TimoColors.cardTop, TimoColors.cardBottom]), border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('CAMERA', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textSecondary)),
        const SizedBox(height: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Resolution', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: TimoColors.textSecondary)), const SizedBox(height: 8), Row(children: [
          Expanded(child: _SegmentButton('320×240', resolution == '320x240', () => onResolutionChange('320x240'))),
          const SizedBox(width: 8),
          Expanded(child: _SegmentButton('640×480', resolution == '640x480', () => onResolutionChange('640x480'))),
        ])]),
        const SizedBox(height: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Quality', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: TimoColors.textSecondary)), const SizedBox(height: 8), Row(children: [
          Expanded(child: _SegmentButton('Low', quality == 'Low', () => onQualityChange('Low'))),
          const SizedBox(width: 8),
          Expanded(child: _SegmentButton('High', quality == 'High', () => onQualityChange('High'))),
        ])]),
      ]),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SegmentButton(this.label, this.active, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? TimoColors.primary : TimoColors.inset,
        border: Border.all(color: active ? TimoColors.primary : TimoColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: active ? Colors.white : TimoColors.textSecondary))),
    )));
  }
}

class _StreamStatsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [TimoColors.cardTop, TimoColors.cardBottom]), border: Border.all(color: TimoColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('STREAM STATS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: TimoColors.textSecondary)),
        const SizedBox(height: 12),
        _StatRow('Resolution', '640×480'),
        _StatRow('FPS', '15'),
        _StatRow('Latency', '45ms'),
        _StatRow('Bitrate', '1.2 Mbps'),
        _StatRow('Codec', 'MJPEG'),
      ]),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label, value;
  const _StatRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
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
