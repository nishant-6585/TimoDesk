import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
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

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.member.fullName);
    _phone = TextEditingController(text: widget.member.phone ?? '');
    _role = TextEditingController(text: widget.member.role ?? '');
    _personType = widget.member.personType ?? 'Employee';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _role.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await updateStaff(widget.member.id, {
        'full_name': _name.text,
        'phone': _phone.text,
        'person_type': _personType,
        'role': _role.text,
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
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
