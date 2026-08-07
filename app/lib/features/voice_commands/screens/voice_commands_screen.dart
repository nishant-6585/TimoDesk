import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../providers/voice_commands_provider.dart';

/// Voice Commands — the catalog of what the robot listens for. Backed by the
/// spine's /voice-commands endpoints (Supabase). Editing a command's phrases,
/// enabling/disabling it, or adding a new one repoints the robot with NO APK
/// rebuild — the config-driven core of the voice architecture.
class VoiceCommandsScreen extends ConsumerWidget {
  const VoiceCommandsScreen({Key? key}) : super(key: key);

  static const _skillOrder = ['navigation', 'reception', 'social', 'system', 'persona'];
  static const _skillLabels = {
    'navigation': 'Navigation',
    'reception': 'Reception',
    'social': 'Social',
    'system': 'System',
    'persona': 'Persona',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(voiceCommandsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Voice Commands',
                  style: GoogleFonts.inter(
                      fontSize: 22, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary)),
              const SizedBox(height: 4),
              Text('What Mini listens for — edit a phrase, toggle a command, or add one. No rebuild.',
                  style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
            ]),
          ),
          ElevatedButton.icon(
            onPressed: () => _edit(context, ref, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add command'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MikeeColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        _infoBanner(),
        const SizedBox(height: 20),
        commands.when(
          loading: () => const Center(
              child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator())),
          error: (e, _) => _errorCard('$e'),
          data: (list) {
            if (list.isEmpty) return _emptyCard();
            final bySkill = <String, List<VoiceCommand>>{};
            for (final c in list) {
              (bySkill[c.skill] ??= []).add(c);
            }
            final skills = [
              ..._skillOrder.where(bySkill.containsKey),
              ...bySkill.keys.where((s) => !_skillOrder.contains(s)),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final skill in skills) ...[
                  _skillHeader(_skillLabels[skill] ?? skill, bySkill[skill]!.length),
                  const SizedBox(height: 10),
                  for (final c in bySkill[skill]!)
                    _CommandCard(command: c, onChanged: () => ref.invalidate(voiceCommandsProvider)),
                  const SizedBox(height: 18),
                ],
              ],
            );
          },
        ),
      ]),
    );
  }

  Widget _skillHeader(String label, int count) => Row(children: [
        Text(label.toUpperCase(),
            style: GoogleFonts.robotoMono(
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
                color: MikeeColors.primary)),
        const SizedBox(width: 8),
        Text('$count',
            style: GoogleFonts.robotoMono(fontSize: 11, color: MikeeColors.textSecondary)),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: MikeeColors.borderFaint)),
      ]);

  Widget _infoBanner() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MikeeColors.cardTop,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MikeeColors.border),
        ),
        child: Row(children: [
          const Icon(Icons.graphic_eq, color: MikeeColors.primary, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Reflex commands run on-device (offline, instant). LLM commands are handled by the '
              'conversational brain for natural phrasing. Disabling a command stops the robot acting on it.',
              style: GoogleFonts.inter(fontSize: 12.5, color: MikeeColors.textSecondary, height: 1.4),
            ),
          ),
        ]),
      );

  Widget _errorCard(String msg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: MikeeColors.cardTop,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(height: 8),
          Text('Could not load voice commands',
              style: GoogleFonts.inter(color: MikeeColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(msg, style: GoogleFonts.robotoMono(fontSize: 11, color: MikeeColors.textSecondary)),
        ]),
      );

  Widget _emptyCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MikeeColors.cardTop,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MikeeColors.border),
        ),
        child: Text('No voice commands yet — add one to get started.',
            style: GoogleFonts.inter(color: MikeeColors.textSecondary)),
      );

  Future<void> _edit(BuildContext context, WidgetRef ref, VoiceCommand? existing) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CommandDialog(existing: existing),
    );
    if (saved == true) ref.invalidate(voiceCommandsProvider);
  }
}

class _CommandCard extends ConsumerStatefulWidget {
  const _CommandCard({required this.command, required this.onChanged});
  final VoiceCommand command;
  final VoidCallback onChanged;

  @override
  ConsumerState<_CommandCard> createState() => _CommandCardState();
}

class _CommandCardState extends ConsumerState<_CommandCard> {
  bool _busy = false;

  Future<void> _toggle(bool v) async {
    setState(() => _busy = true);
    try {
      await voiceCommandPatch(widget.command.id, {'enabled': v});
      widget.onChanged();
    } catch (e) {
      if (mounted) _snack('Update failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: MikeeColors.cardTop,
        title: Text('Delete "${widget.command.label}"?',
            style: GoogleFonts.inter(color: MikeeColors.textPrimary)),
        content: Text('The robot will stop recognizing this command.',
            style: GoogleFonts.inter(color: MikeeColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await voiceCommandRemove(widget.command.id);
      widget.onChanged();
    } catch (e) {
      if (mounted) _snack('Delete failed: $e');
    }
  }

  Future<void> _editDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CommandDialog(existing: widget.command),
    );
    if (saved == true) widget.onChanged();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final c = widget.command;
    final dim = c.enabled ? 1.0 : 0.5;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MikeeColors.cardTop,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MikeeColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Opacity(
              opacity: dim,
              child: Row(children: [
                Flexible(
                  child: Text(c.label,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 15, fontWeight: FontWeight.w600, color: MikeeColors.textPrimary)),
                ),
                const SizedBox(width: 8),
                _tag(c.tier == 'llm' ? 'LLM' : 'REFLEX',
                    c.tier == 'llm' ? Colors.purpleAccent : MikeeColors.primary),
                if (c.confirm) ...[const SizedBox(width: 6), _tag('CONFIRM', Colors.amber)],
              ]),
            ),
          ),
          if (_busy)
            const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Switch(
              value: c.enabled,
              activeThumbColor: MikeeColors.primary,
              onChanged: _toggle,
            ),
          IconButton(
              onPressed: _editDialog,
              icon: const Icon(Icons.edit_outlined, size: 18, color: MikeeColors.textSecondary),
              tooltip: 'Edit'),
          IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, size: 18, color: MikeeColors.textSecondary),
              tooltip: 'Delete'),
        ]),
        const SizedBox(height: 4),
        Opacity(
          opacity: dim,
          child: Text('intent: ${c.intent}',
              style: GoogleFonts.robotoMono(fontSize: 11, color: MikeeColors.textSecondary)),
        ),
        const SizedBox(height: 10),
        Opacity(
          opacity: dim,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final p in c.examplePhrases) _phraseChip(p)],
          ),
        ),
      ]),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text,
            style: GoogleFonts.robotoMono(
                fontSize: 9, letterSpacing: 0.6, fontWeight: FontWeight.w600, color: color)),
      );

  Widget _phraseChip(String p) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: MikeeColors.inset,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: MikeeColors.borderFaint),
        ),
        child: Text('"$p"',
            style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textPrimary)),
      );
}

/// Add / edit dialog. On create, intent + skill are set; on edit they're read-only
/// (the intent is the code contract — rename the label instead).
class _CommandDialog extends StatefulWidget {
  const _CommandDialog({this.existing});
  final VoiceCommand? existing;

  @override
  State<_CommandDialog> createState() => _CommandDialogState();
}

class _CommandDialogState extends State<_CommandDialog> {
  late final TextEditingController _intent;
  late final TextEditingController _label;
  late final TextEditingController _phrases;
  String _skill = 'system';
  String _tier = 'reflex';
  bool _confirm = false;
  bool _busy = false;
  String? _error;

  static const _skills = ['navigation', 'reception', 'social', 'system', 'persona'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _intent = TextEditingController(text: e?.intent ?? '');
    _label = TextEditingController(text: e?.label ?? '');
    _phrases = TextEditingController(text: e?.examplePhrases.join('\n') ?? '');
    _skill = e?.skill ?? 'system';
    _tier = e?.tier ?? 'reflex';
    _confirm = e?.confirm ?? false;
  }

  @override
  void dispose() {
    _intent.dispose();
    _label.dispose();
    _phrases.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final phrases = _phrases.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (_label.text.trim().isEmpty) {
      setState(() => _error = 'Label is required');
      return;
    }
    if (phrases.isEmpty) {
      setState(() => _error = 'At least one example phrase is required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.existing == null) {
        if (_intent.text.trim().isEmpty) {
          setState(() {
            _error = 'Intent is required';
            _busy = false;
          });
          return;
        }
        await voiceCommandAdd(
          intent: _intent.text.trim(),
          label: _label.text.trim(),
          skill: _skill,
          examplePhrases: phrases,
          tier: _tier,
          confirm: _confirm,
        );
      } else {
        await voiceCommandPatch(widget.existing!.id, {
          'label': _label.text.trim(),
          'skill': _skill,
          'tier': _tier,
          'confirm': _confirm,
          'example_phrases': phrases,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      backgroundColor: MikeeColors.cardTop,
      title: Text(editing ? 'Edit command' : 'Add command',
          style: GoogleFonts.inter(color: MikeeColors.textPrimary, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _field(_intent, 'Intent (code contract)',
                hint: 'e.g. patrol', enabled: !editing),
            const SizedBox(height: 12),
            _field(_label, 'Label', hint: 'e.g. Patrol rounds'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _dropdown('Skill', _skill, _skills, (v) => setState(() => _skill = v))),
              const SizedBox(width: 12),
              Expanded(child: _dropdown('Tier', _tier, const ['reflex', 'llm'], (v) => setState(() => _tier = v))),
            ]),
            const SizedBox(height: 12),
            _field(_phrases, 'Example phrases (one per line)',
                hint: 'start patrol\nmake your rounds', maxLines: 5),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _confirm,
              onChanged: (v) => setState(() => _confirm = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: MikeeColors.primary,
              title: Text('Confirm before acting (physical / destructive)',
                  style: GoogleFonts.inter(fontSize: 12.5, color: MikeeColors.textSecondary)),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: MikeeColors.primary, foregroundColor: Colors.white),
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(editing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label,
          {String? hint, int maxLines = 1, bool enabled = true}) =>
      TextField(
        controller: c,
        enabled: enabled,
        maxLines: maxLines,
        style: GoogleFonts.inter(color: MikeeColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: GoogleFonts.inter(color: MikeeColors.textSecondary, fontSize: 12),
          hintStyle: GoogleFonts.inter(color: MikeeColors.textSecondary.withValues(alpha: 0.5)),
          filled: true,
          fillColor: MikeeColors.inset,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: MikeeColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: MikeeColors.border)),
        ),
      );

  Widget _dropdown(String label, String value, List<String> options, ValueChanged<String> onChanged) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(color: MikeeColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: MikeeColors.inset,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: MikeeColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: MikeeColors.cardTop,
              style: GoogleFonts.inter(color: MikeeColors.textPrimary, fontSize: 14),
              items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
              onChanged: (v) => v != null ? onChanged(v) : null,
            ),
          ),
        ),
      ]);
}
