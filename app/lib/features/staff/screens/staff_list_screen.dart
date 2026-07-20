import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../services/spine/spine_provider.dart';
import '../providers/staff_list_provider.dart';

/// View / edit / delete enrolled staff (DPDP-compliant erasure).
class StaffListScreen extends ConsumerWidget {
  const StaffListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffListProvider);

    return Scaffold(
      backgroundColor: MikeeColors.background,
      appBar: AppBar(
        title: const Text('Enrolled Staff'),
        backgroundColor: MikeeColors.surface,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(staffListProvider),
          ),
        ],
      ),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                const SizedBox(height: 12),
                Text('Failed to load staff:\n$e',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: MikeeColors.textSecondary)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(staffListProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (staff) {
          if (staff.isEmpty) {
            return Center(
              child: Text('No staff enrolled yet.',
                  style: GoogleFonts.inter(color: MikeeColors.textSecondary)),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: staff.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _StaffCard(member: staff[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StaffCard extends ConsumerWidget {
  final StaffMember member;
  const _StaffCard({required this.member});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MikeeColors.cardTop, MikeeColors.cardBottom],
        ),
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _StaffAvatar(member: member),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.fullName,
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: MikeeColors.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  [
                    if (member.personType != null) member.personType,
                    if (member.role != null && member.role!.isNotEmpty) member.role,
                    if (member.phone != null && member.phone!.isNotEmpty) member.phone,
                  ].join(' · '),
                  style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: member.embeddingCount > 0
                        ? MikeeColors.success.withOpacity(0.12)
                        : Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${member.embeddingCount} face${member.embeddingCount == 1 ? '' : 's'} enrolled',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: member.embeddingCount > 0 ? MikeeColors.success : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () => _openEdit(context, ref),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  void _openEdit(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _EditStaffDialog(member: member, ref: ref),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MikeeColors.surface,
        title: const Text('Delete staff?'),
        content: Text(
          'This permanently deletes ${member.fullName} and erases their '
          '${member.embeddingCount} enrolled face embedding(s). This cannot be undone.',
          style: GoogleFonts.inter(color: MikeeColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final erased = await deleteStaff(member.id);
      ref.invalidate(staffListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted ${member.fullName} ($erased embedding(s) erased)')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }
}

/// Round avatar — shows the enrolled face photo when available, otherwise the
/// first initial. Falls back to the initial if the signed URL fails or expires.
class _StaffAvatar extends StatelessWidget {
  final StaffMember member;
  const _StaffAvatar({required this.member});

  @override
  Widget build(BuildContext context) {
    final initial = member.fullName.isNotEmpty ? member.fullName[0].toUpperCase() : '?';
    final fallback = CircleAvatar(
      radius: 24,
      backgroundColor: MikeeColors.primary.withOpacity(0.15),
      child: Text(
        initial,
        style: GoogleFonts.inter(color: MikeeColors.primary, fontWeight: FontWeight.bold, fontSize: 18),
      ),
    );

    final url = member.photoUrl;
    if (url == null || url.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _EditStaffDialog extends StatefulWidget {
  final StaffMember member;
  final WidgetRef ref;
  const _EditStaffDialog({required this.member, required this.ref});

  @override
  State<_EditStaffDialog> createState() => _EditStaffDialogState();
}

class _EditStaffDialogState extends State<_EditStaffDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _role;
  late String _personType;
  bool _saving = false;

  // Desk/location pose. Starts as the member's saved pose; Capture replaces it
  // with the robot's live SLAM position, the clear button nulls it. Only sent
  // on save when it actually changed (_deskDirty).
  Map<String, double>? _deskPose;
  bool _deskDirty = false;
  bool _capturingDesk = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.member.fullName);
    _phone = TextEditingController(text: widget.member.phone ?? '');
    _role = TextEditingController(text: widget.member.role ?? '');
    _personType = widget.member.personType ?? 'Employee';
    if (widget.member.hasDesk) {
      _deskPose = {
        'x': widget.member.deskX!,
        'y': widget.member.deskY!,
        'z': widget.member.deskZ ?? 0,
        'rotation': widget.member.deskRotation ?? 0,
      };
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _role.dispose();
    super.dispose();
  }

  /// Capture the robot's current SLAM pose (via the spine) as this person's
  /// desk. Requires the robot online and localized, parked at the desk.
  Future<void> _captureDesk() async {
    setState(() => _capturingDesk = true);
    try {
      final pose = await widget.ref.read(spineProvider.notifier).getPosition();
      if (!mounted) return;
      if (pose == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not read robot position — is the robot online and localized on its map?'),
        ));
      } else {
        setState(() {
          _deskPose = pose;
          _deskDirty = true;
        });
      }
    } finally {
      if (mounted) setState(() => _capturingDesk = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await updateStaff(widget.member.id, {
        'full_name': _name.text,
        'phone': _phone.text,
        'person_type': _personType,
        'role': _role.text,
        if (_deskDirty) 'desk_pose': _deskPose,
      });
      widget.ref.invalidate(staffListProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MikeeColors.surface,
      title: const Text('Edit Staff'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name')),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _personType,
              decoration: const InputDecoration(labelText: 'Person Type'),
              items: const [
                DropdownMenuItem(value: 'Employee', child: Text('Employee')),
                DropdownMenuItem(value: 'Staff', child: Text('Staff')),
              ],
              onChanged: (v) => setState(() => _personType = v ?? 'Employee'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _role, decoration: const InputDecoration(labelText: 'Role')),
            const SizedBox(height: 16),
            _buildDeskRow(),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving || _capturingDesk ? null : _save,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  /// Desk location row — shows the captured pose (if any) with capture /
  /// recapture / clear actions. Park the robot at the desk before capturing.
  Widget _buildDeskRow() {
    final has = _deskPose != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: MikeeColors.background,
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(has ? Icons.place : Icons.place_outlined,
              size: 20, color: has ? MikeeColors.primary : MikeeColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Desk Location',
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600, color: MikeeColors.textPrimary)),
                Text(
                  has
                      ? 'x=${_deskPose!['x']!.toStringAsFixed(2)}, y=${_deskPose!['y']!.toStringAsFixed(2)}'
                      : 'Park the robot at the desk, then capture.',
                  style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textSecondary),
                ),
              ],
            ),
          ),
          if (has)
            IconButton(
              tooltip: 'Clear desk location',
              icon: const Icon(Icons.close, size: 16),
              onPressed: _capturingDesk
                  ? null
                  : () => setState(() {
                        _deskPose = null;
                        _deskDirty = true;
                      }),
            ),
          TextButton.icon(
            onPressed: _capturingDesk ? null : _captureDesk,
            icon: _capturingDesk
                ? const SizedBox(
                    height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location, size: 16),
            label: Text(has ? 'Recapture' : 'Capture'),
          ),
        ],
      ),
    );
  }
}
