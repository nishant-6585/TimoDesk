import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'providers.dart'; // chassisProvider (native getPosition for desk capture)
import 'services/face_enroll.dart';

const _orange = Color(0xFFFF6B35);
const _bg = Color(0xFF0F0F0F);
const _panel = Color(0xFF151515);
const _panel2 = Color(0xFF1A1A1A);
const _line = Color(0xFF262626);
const _ink = Color(0xFFF4F1EE);
const _muted = Color(0xFF9A9A9A);
const _green = Color(0xFF4ADE80);
const _indigo = Color(0xFF6366F1);

// ── Staff model ──────────────────────────────────────────────────────────────
class _StaffMember {
  final String id;
  final String fullName;
  final String personType;
  final String? role;
  final bool active;
  final int embeddingCount;
  final String createdAt;
  final String? photoUrl;
  const _StaffMember({
    required this.id,
    required this.fullName,
    required this.personType,
    this.role,
    required this.active,
    required this.embeddingCount,
    required this.createdAt,
    this.photoUrl,
  });
  factory _StaffMember.fromJson(Map<String, dynamic> j) => _StaffMember(
        id: j['id'] as String,
        fullName: j['full_name'] as String? ?? '—',
        personType: j['person_type'] as String? ?? 'Staff',
        role: j['role'] as String?,
        active: j['active'] as bool? ?? true,
        embeddingCount: j['embedding_count'] as int? ?? 0,
        createdAt: j['created_at'] as String? ?? '',
        photoUrl: j['photo_url'] as String?,
      );
}

// ── Pose plan ────────────────────────────────────────────────────────────────
class _Pose {
  final String name;
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

// ── Avatar color palette ─────────────────────────────────────────────────────
const _avatarColors = [
  Color(0xFF6366F1), Color(0xFFEC4899), Color(0xFF14B8A6),
  Color(0xFFF59E0B), Color(0xFF10B981), Color(0xFF8B5CF6),
  Color(0xFFEF4444), Color(0xFF3B82F6), Color(0xFFFF6B35),
];

Color _avatarColor(String name) =>
    _avatarColors[name.codeUnitAt(0) % _avatarColors.length];

// ── Root screen with tabs ────────────────────────────────────────────────────
class EnrollScreen extends StatelessWidget {
  const EnrollScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text('Enroll Staff', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: _panel2,
          centerTitle: true,
          bottom: const TabBar(
            indicatorColor: _orange,
            labelColor: _orange,
            unselectedLabelColor: _muted,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: [
              Tab(icon: Icon(Icons.grid_view_rounded, size: 18), text: 'Gallery'),
              Tab(icon: Icon(Icons.person_add_alt_1_rounded, size: 18), text: 'Register'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _GalleryTab(),
            _RegisterTab(),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GALLERY TAB
// ══════════════════════════════════════════════════════════════════════════════
class _GalleryTab extends StatefulWidget {
  const _GalleryTab();

  @override
  State<_GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<_GalleryTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<_StaffMember>? _staff;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http
          .get(
            Uri.parse('${RobotConfig.spineBaseUrl}/staff'),
            headers: {'Authorization': 'Bearer ${RobotConfig.authToken}'},
          )
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final list = (data['staff'] as List)
            .map((e) => _StaffMember.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _staff = list;
          _loading = false;
        });
      } else {
        setState(() {
          _error = data['reason'] as String? ?? 'Server error';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString().contains('SocketException')
            ? 'Cannot reach spine — check Spine URL in Settings'
            : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _delete(_StaffMember s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel2,
        title: const Text('Remove staff member?'),
        content: Text(
          '${s.fullName} and all ${s.embeddingCount} face poses will be permanently erased.',
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final res = await http.delete(
        Uri.parse('${RobotConfig.spineBaseUrl}/staff/${Uri.encodeComponent(s.id)}'),
        headers: {'Authorization': 'Bearer ${RobotConfig.authToken}'},
      ).timeout(const Duration(seconds: 10));
      final ok = (jsonDecode(res.body) as Map<String, dynamic>)['ok'] == true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? '${s.fullName} removed' : 'Delete failed'),
          backgroundColor: ok ? Colors.green.shade800 : Colors.redAccent,
        ));
        if (ok) _load();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delete failed — network error'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _orange));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 64, color: _muted),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 14)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(backgroundColor: _orange),
            ),
          ]),
        ),
      );
    }

    final staff = _staff ?? [];

    if (staff.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.people_outline_rounded, size: 72, color: _muted),
          const SizedBox(height: 16),
          const Text('No staff enrolled yet',
              style: TextStyle(color: _muted, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Go to the Register tab to add staff members.',
              style: TextStyle(color: Color(0xFF5A5A5A), fontSize: 13)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Refresh'),
            style: FilledButton.styleFrom(backgroundColor: _panel2),
          ),
        ]),
      );
    }

    return RefreshIndicator(
      color: _orange,
      backgroundColor: _panel2,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Row(children: [
                Text('${staff.length} member${staff.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 18, color: _muted),
                  tooltip: 'Refresh',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisExtent: 200,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _StaffCard(staff: staff[i], onDelete: () => _delete(staff[i])),
                childCount: staff.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Staff card ────────────────────────────────────────────────────────────────
class _StaffCard extends StatelessWidget {
  final _StaffMember staff;
  final VoidCallback onDelete;
  const _StaffCard({required this.staff, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final initials = staff.fullName
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();
    final color = _avatarColor(staff.fullName);
    final typeColor = staff.personType == 'Employee' ? _indigo : _orange;

    return Container(
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar — real face photo when enrolled, else colored initials
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.15),
                  border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
                ),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                child: (staff.photoUrl != null && staff.photoUrl!.isNotEmpty)
                    ? Image.network(
                        staff.photoUrl!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        // Fall back to initials if the signed URL fails / expires.
                        errorBuilder: (_, __, ___) => Text(initials,
                            style: TextStyle(
                                color: color, fontSize: 24, fontWeight: FontWeight.w800)),
                      )
                    : Text(initials,
                        style: TextStyle(
                            color: color, fontSize: 24, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 12),
              // Name
              Text(
                staff.fullName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _ink, fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              // Type badge + pose count
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: typeColor.withValues(alpha: 0.35)),
                  ),
                  child: Text(staff.personType,
                      style: TextStyle(
                          color: typeColor, fontSize: 9, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.face_rounded, size: 11,
                      color: staff.embeddingCount > 0 ? _green : _muted),
                  const SizedBox(width: 3),
                  Text('${staff.embeddingCount}',
                      style: TextStyle(
                          color: staff.embeddingCount > 0 ? _green : _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ]),
              ]),
            ],
          ),
        ),
        // Delete button — top-right
        Positioned(
          top: 6,
          right: 6,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: onDelete,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, size: 15, color: Colors.redAccent),
              ),
            ),
          ),
        ),
        // Active dot — top-left
        Positioned(
          top: 10,
          left: 10,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: staff.active ? _green : _muted,
              boxShadow: staff.active
                  ? [BoxShadow(color: _green.withValues(alpha: 0.5), blurRadius: 5)]
                  : null,
            ),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// REGISTER TAB  (the original enrollment flow, self-contained)
// ══════════════════════════════════════════════════════════════════════════════
class _RegisterTab extends ConsumerStatefulWidget {
  const _RegisterTab();

  @override
  ConsumerState<_RegisterTab> createState() => _RegisterTabState();
}

class _RegisterTabState extends ConsumerState<_RegisterTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Tunable gates.
  static const double _minFaceHeight = 0.28;
  static const double _maxFaceHeight = 0.90;
  static const double _yawTurn = 18;
  static const double _yawFront = 10;
  static const double _pitchTurn = 12;
  static const double _pitchFront = 10;
  static const int _stableNeeded = 4;
  static const int _getReadySeconds = 3;
  static const Duration _pollEvery = Duration(milliseconds: 250);

  // Phases: form → capture → uploading → done
  String _phase = 'form';

  // Form
  final _nameCtr = TextEditingController();
  final _phoneCtr = TextEditingController();
  String _personType = 'Employee';
  bool _consent = false;
  // Optional desk/location pose — capture the robot's SLAM position so Timo can
  // navigate to this person's desk later (#71). Park the robot at the desk first.
  Map<String, double>? _deskPose;
  bool _capturingDesk = false;

  // Capture
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast, minFaceSize: 0.15),
  );
  Timer? _pollTimer;
  Timer? _getReadyTimer;
  bool _detecting = false;
  Uint8List? _latestFrame;
  int? _imgW;
  int? _imgH;

  int _poseIndex = 0;
  String _capPhase = 'getReady';
  int _getReadyLeft = _getReadySeconds;
  int _stable = 0;
  bool _faceReady = false;
  String _hint = 'Starting…';
  final List<Uint8List> _frames = [];

  // Upload
  String _uploadMsg = '';
  String? _doneError;

  // SDK face registration (post-upload)
  bool _sdkEnrolling = false;
  String? _sdkResult;

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

  // ── Capture flow ─────────────────────────────────────────────────────────
  void _startCapture() {
    setState(() {
      _phase = 'capture';
      _poseIndex = 0;
      _frames.clear();
    });
    _pollTimer = Timer.periodic(_pollEvery, (_) => _tick());
    _startPose();
  }

  /// Capture the robot's current SLAM pose as this person's desk. Ensures chassis
  /// control is running first (native getPosition no-ops otherwise), mirroring the
  /// nav-points capture flow. Requires the robot to be localized on its map.
  Future<void> _captureDesk() async {
    setState(() => _capturingDesk = true);
    try {
      final chassis = ref.read(chassisProvider);
      if (!chassis.isRunning) {
        await ref.read(chassisProvider.notifier).startChassisControl();
      }
      final pose = await ref.read(chassisProvider.notifier).getPosition();
      if (!mounted) return;
      if (pose == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not read position — make sure the robot is localized on its map.'),
        ));
      } else {
        setState(() => _deskPose = pose);
      }
    } finally {
      if (mounted) setState(() => _capturingDesk = false);
    }
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

  Future<void> _tick() async {
    if (_detecting) return;
    _detecting = true;
    try {
      final bytes = await _fetchSnapshot();
      if (bytes == null || !mounted) return;
      _latestFrame = bytes;
      if (_imgW == null) await _decodeDims(bytes);
      if (_capPhase != 'detecting') {
        setState(() {});
        return;
      }
      await _detectAndGate(bytes);
    } catch (_) {
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
      if (b.length < 4 || b[0] != 0xff || b[1] != 0xd8) return null;
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

  Future<void> _detectAndGate(Uint8List bytes) async {
    final w = _imgW, h = _imgH;
    if (w == null || h == null) return;

    final tmp = File('${Directory.systemTemp.path}/mikee_enroll_frame.jpg');
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
      final yaw = f.headEulerAngleY ?? 0;
      final pitch = f.headEulerAngleX ?? 0;

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

    if (ready && _stable >= _stableNeeded && _capPhase == 'detecting') _capture();
  }

  bool _orientationMatches(String pose, double yaw, double pitch) {
    switch (pose) {
      case 'Front': return yaw.abs() < _yawFront && pitch.abs() < _pitchFront;
      case 'Left': return yaw >= _yawTurn;
      case 'Right': return yaw <= -_yawTurn;
      case 'Up': return pitch >= _pitchTurn;
      case 'Down': return pitch <= -_pitchTurn;
    }
    return false;
  }

  Future<void> _capture() async {
    final frame = _latestFrame;
    if (frame == null) return;
    setState(() => _capPhase = 'captured');
    _frames.add(frame);

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
          setState(() => _phase = 'form');
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

  // ── Backend ──────────────────────────────────────────────────────────────
  Future<String?> _checkDuplicate(Uint8List frame) async {
    try {
      final res = await http
          .post(
            Uri.parse('${RobotConfig.spineBaseUrl}/check-face'),
            headers: {'Authorization': 'Bearer ${RobotConfig.authToken}', 'Content-Type': 'application/json'},
            body: jsonEncode({'image_base64': base64Encode(frame)}),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] == true && data['match'] == true) return data['name'] as String?;
    } catch (_) {}
    return null;
  }

  Future<bool> _showDuplicateDialog(String name) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel2,
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
              headers: {'Authorization': 'Bearer ${RobotConfig.authToken}', 'Content-Type': 'application/json'},
              body: jsonEncode({
                'full_name': _nameCtr.text,
                'phone': _phoneCtr.text,
                'person_type': _personType,
                'consent': true,
                'consent_ref': '$consentRef-pose-$i',
                'image_base64': base64Encode(_frames[i]),
                // Pose 0 is the Front shot — use it as the gallery thumbnail.
                'set_thumbnail': i == 0,
                // Send the desk pose once (with pose 0); spine writes it to staff.
                if (i == 0 && _deskPose != null) 'desk_pose': _deskPose,
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

  Future<void> _enrollSdk() async {
    setState(() {
      _sdkEnrolling = true;
      _sdkResult = null;
    });
    final ok = await FaceEnroll.saveFace(_nameCtr.text.trim());
    if (!mounted) return;
    setState(() {
      _sdkEnrolling = false;
      _sdkResult = ok
          ? 'Registered with Mikee ✓ — will be greeted by name'
          : 'Robot not reachable — try again while on the robot';
    });
  }

  void _reset() {
    setState(() {
      _phase = 'form';
      _sdkResult = null;
      _sdkEnrolling = false;
      _nameCtr.clear();
      _phoneCtr.clear();
      _personType = 'Employee';
      _consent = false;
      _frames.clear();
    });
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return switch (_phase) {
      'form' => _buildForm(),
      'capture' => _buildCapture(),
      'uploading' => _buildUploading(),
      _ => _buildDone(),
    };
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: _panel2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _buildForm() {
    final canStart = _nameCtr.text.trim().isNotEmpty && _consent;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Enter details, then capture 5 quick poses.',
            style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 20),
        TextField(
          controller: _nameCtr,
          style: const TextStyle(fontSize: 18),
          textCapitalization: TextCapitalization.words,
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
          initialValue: _personType,
          dropdownColor: _panel2,
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
        const SizedBox(height: 12),
        // Desk location (optional) — capture the robot's SLAM pose so Timo can
        // navigate to this person's desk later. Park the robot at the desk first.
        Container(
          decoration: BoxDecoration(
            color: _panel2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(children: [
            Icon(_deskPose != null ? Icons.place : Icons.place_outlined,
                color: _deskPose != null ? _orange : Colors.white38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Desk location (optional)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  _deskPose != null
                      ? 'Captured: x=${_deskPose!['x']!.toStringAsFixed(2)}, y=${_deskPose!['y']!.toStringAsFixed(2)}'
                      : 'Park the robot at the desk, then capture.',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ]),
            ),
            if (_deskPose != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                onPressed: _capturingDesk ? null : () => setState(() => _deskPose = null),
              ),
            TextButton.icon(
              onPressed: _capturingDesk ? null : _captureDesk,
              icon: _capturingDesk
                  ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location, size: 16, color: _orange),
              label: Text(_deskPose != null ? 'Recapture' : 'Capture',
                  style: const TextStyle(color: _orange)),
            ),
          ]),
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

  Widget _buildCapture() {
    final border = _capPhase == 'captured' || _faceReady ? _green : _orange;
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
            style: const TextStyle(
                color: _orange, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 12),
        Text(_pose.instruction,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        CircleAvatar(
          radius: 34,
          backgroundColor: Colors.black45,
          child: Text('$_getReadyLeft',
              style: const TextStyle(
                  color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
        ),
      ]);
    }
    if (_capPhase == 'checking') {
      return const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
        SizedBox(height: 16),
        Text('Checking if already enrolled…',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ]);
    }
    if (_capPhase == 'captured') {
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.check_circle, size: 80, color: _green),
        const SizedBox(height: 12),
        Text('Captured ${_pose.name}',
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      ]);
    }
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('Step ${_poseIndex + 1} of ${_posePlan.length}',
          style: const TextStyle(color: Colors.white70, fontSize: 14)),
      const SizedBox(height: 8),
      Text(_pose.instruction,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      Icon(_faceReady ? Icons.check_circle : Icons.face,
          size: 72, color: _faceReady ? _green : _orange),
      const SizedBox(height: 14),
      Text(_hint,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      if (_faceReady) ...[
        const SizedBox(height: 10),
        SizedBox(
          width: 160,
          child: LinearProgressIndicator(
            value: (_stable / _stableNeeded).clamp(0.0, 1.0),
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(_green),
          ),
        ),
      ],
    ]);
  }

  Widget _buildUploading() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(color: _orange),
          const SizedBox(height: 20),
          Text(_uploadMsg,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
        ]),
      );

  Widget _buildDone() {
    final ok = _doneError == null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(ok ? Icons.check_circle : Icons.error,
              size: 96, color: ok ? _green : Colors.redAccent),
          const SizedBox(height: 20),
          Text(ok ? 'Enrolled!' : 'Enrollment failed',
              style: const TextStyle(
                  color: _ink, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_doneError ?? '${_nameCtr.text} · $_uploadMsg',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),

          if (ok) ...[
            const SizedBox(height: 24),
            const Divider(color: Color(0xFF262626)),
            const SizedBox(height: 16),
            const Text('Register with Mikee Robot',
                style: TextStyle(
                    color: _ink, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Stay in front of the robot camera and tap below.\nMikee will capture and remember your face on-device for instant recognition.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            if (_sdkResult != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _sdkResult!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _sdkResult!.contains('✓') ? _green : Colors.orangeAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed:
                  _sdkEnrolling || _sdkResult?.contains('✓') == true ? null : _enrollSdk,
              icon: _sdkEnrolling
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(_sdkResult?.contains('✓') == true
                      ? Icons.check_circle
                      : Icons.face_retouching_natural),
              label: Text(_sdkEnrolling
                  ? 'Capturing…'
                  : _sdkResult?.contains('✓') == true
                      ? 'Registered with Mikee'
                      : 'Register with Mikee Robot'),
              style: FilledButton.styleFrom(
                backgroundColor: _indigo,
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
              ),
            ),
          ],

          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
              label: const Text('Enroll Another'),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                  backgroundColor: _orange,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14)),
              child: const Text('DONE',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
          ]),
        ]),
      ),
    );
  }
}
