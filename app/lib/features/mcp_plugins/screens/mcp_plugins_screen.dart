import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../providers/mcp_plugins_provider.dart';

/// MCP Plugins — manage the external MCP servers (Slack, Microsoft 365, CRM,
/// ticketing, …) Timo's voice brain can use as tools. Backed by the spine's
/// /mcp/plugins endpoints; tokens are write-only and never displayed.
class McpPluginsScreen extends ConsumerWidget {
  const McpPluginsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(mcpPluginsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MCP Plugins',
                style: GoogleFonts.inter(
                    fontSize: 22, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary)),
            const SizedBox(height: 4),
            Text('External tool servers Timo can use — calendar, messaging, CRM, ticketing',
                style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
          ]),
          ElevatedButton.icon(
            onPressed: () => _addPlugin(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add plugin'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MikeeColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        _infoBanner(),
        const SizedBox(height: 16),
        plugins.when(
          loading: () => const Center(
              child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator())),
          error: (e, _) => _errorCard('$e'),
          data: (list) => list.isEmpty
              ? _emptyCard()
              : Column(
                  children: [for (final p in list) _PluginCard(plugin: p)],
                ),
        ),
      ]),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MikeeColors.info.withOpacity(0.08),
        border: Border.all(color: MikeeColors.info.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, size: 18, color: MikeeColors.info),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Enabled plugins become tools for the voice brain when MCP_TOOLS_ENABLED=true is set '
            'in the spine. Hosted MCP servers need an OAuth bearer token, not the service\'s native API key.',
            style: GoogleFonts.inter(fontSize: 12.5, color: MikeeColors.textSecondary, height: 1.4),
          ),
        ),
      ]),
    );
  }

  Widget _emptyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: MikeeColors.cardTop,
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        const Icon(Icons.extension_outlined, size: 40, color: MikeeColors.textMuted),
        const SizedBox(height: 12),
        Text('No MCP plugins yet',
            style: GoogleFonts.inter(
                fontSize: 15, fontWeight: FontWeight.w600, color: MikeeColors.textPrimary)),
        const SizedBox(height: 6),
        Text('Add a plugin to give Timo external tools — e.g. Slack notifications or a Microsoft 365 calendar.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
      ]),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MikeeColors.error.withOpacity(0.08),
        border: Border.all(color: MikeeColors.error.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('Could not load plugins: $message\nIs the spine running?',
          style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.error)),
    );
  }

  Future<void> _addPlugin(BuildContext context, WidgetRef ref) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddPluginDialog(),
    );
    if (added == true) ref.invalidate(mcpPluginsProvider);
  }
}

class _PluginCard extends ConsumerStatefulWidget {
  final McpPlugin plugin;
  const _PluginCard({required this.plugin});

  @override
  ConsumerState<_PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends ConsumerState<_PluginCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() op) async {
    setState(() => _busy = true);
    try {
      await op();
      ref.invalidate(mcpPluginsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e'), backgroundColor: MikeeColors.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plugin;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MikeeColors.cardTop,
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Icon(Icons.extension,
            size: 22, color: p.enabled ? MikeeColors.primary : MikeeColors.textMuted),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(p.name,
                  style: GoogleFonts.inter(
                      fontSize: 15, fontWeight: FontWeight.w600, color: MikeeColors.textPrimary)),
              const SizedBox(width: 8),
              _chip(p.enabled ? 'ENABLED' : 'DISABLED',
                  p.enabled ? MikeeColors.success : MikeeColors.textMuted),
              if (p.hasToken) ...[const SizedBox(width: 6), _chip('TOKEN SET', MikeeColors.info)],
            ]),
            const SizedBox(height: 4),
            Text(p.url,
                style: GoogleFonts.jetBrainsMono(fontSize: 12, color: MikeeColors.textSecondary)),
            if (p.description != null && p.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(p.description!,
                  style: GoogleFonts.inter(fontSize: 12.5, color: MikeeColors.textMuted)),
            ],
          ]),
        ),
        if (_busy)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else ...[
          Switch(
            value: p.enabled,
            activeColor: MikeeColors.primary,
            onChanged: (v) => _run(() => mcpPluginSetEnabled(p.name, v)),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Remove plugin',
            icon: const Icon(Icons.delete_outline, size: 20, color: MikeeColors.textMuted),
            onPressed: () => _confirmRemove(context, p.name),
          ),
        ],
      ]),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Future<void> _confirmRemove(BuildContext context, String name) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MikeeColors.cardTop,
        title: Text('Remove "$name"?',
            style: GoogleFonts.inter(color: MikeeColors.textPrimary, fontWeight: FontWeight.w600)),
        content: Text('The plugin and its stored token are deleted from the spine.',
            style: GoogleFonts.inter(color: MikeeColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: MikeeColors.error)),
          ),
        ],
      ),
    );
    if (yes == true) await _run(() => mcpPluginRemove(name));
  }
}

class _AddPluginDialog extends StatefulWidget {
  const _AddPluginDialog();

  @override
  State<_AddPluginDialog> createState() => _AddPluginDialogState();
}

class _AddPluginDialogState extends State<_AddPluginDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty || url.isEmpty) {
      setState(() => _error = 'Name and URL are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await mcpPluginAdd(
        name: name,
        url: url,
        authorizationToken: _token.text.trim(),
        description: _description.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  InputDecoration _dec(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.inter(color: MikeeColors.textSecondary, fontSize: 13),
        hintStyle: GoogleFonts.inter(color: MikeeColors.textMuted, fontSize: 13),
        enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: MikeeColors.border),
            borderRadius: BorderRadius.all(Radius.circular(10))),
        focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: MikeeColors.primary),
            borderRadius: BorderRadius.all(Radius.circular(10))),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MikeeColors.cardTop,
      title: Text('Add MCP plugin',
          style: GoogleFonts.inter(color: MikeeColors.textPrimary, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _name,
              style: GoogleFonts.inter(color: MikeeColors.textPrimary, fontSize: 14),
              decoration: _dec('Name', 'slack')),
          const SizedBox(height: 12),
          TextField(
              controller: _url,
              style: GoogleFonts.jetBrainsMono(color: MikeeColors.textPrimary, fontSize: 13),
              decoration: _dec('MCP server URL', 'https://mcp.slack.com/mcp')),
          const SizedBox(height: 12),
          TextField(
              controller: _token,
              obscureText: true,
              style: GoogleFonts.jetBrainsMono(color: MikeeColors.textPrimary, fontSize: 13),
              decoration: _dec('OAuth bearer token (optional)', 'stored on the spine, never shown again')),
          const SizedBox(height: 12),
          TextField(
              controller: _description,
              style: GoogleFonts.inter(color: MikeeColors.textPrimary, fontSize: 14),
              decoration: _dec('Description (optional)', 'Team notifications')),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!,
                  style: GoogleFonts.inter(fontSize: 12.5, color: MikeeColors.error)),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: MikeeColors.primary, foregroundColor: Colors.white),
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Add'),
        ),
      ],
    );
  }
}
