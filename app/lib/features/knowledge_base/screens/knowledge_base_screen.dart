import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../providers/kb_provider.dart';
import '../widgets/kb_add_dialogs.dart';
import '../widgets/kb_sources_section.dart';

/// Knowledge Base management — the content Mini's voice answers from.
///
/// Three zones:
///  • Status banner — which halves of the brain are configured (embeddings /
///    LLM / voice grounding) + chunk counts.
///  • "Try a question" — hits the SAME `/ask` pipeline the robot's voice uses,
///    so what you see here is exactly what a visitor will hear.
///  • Chunk list — add text, add a web page, delete (audit-logged).
class KnowledgeBaseScreen extends ConsumerStatefulWidget {
  const KnowledgeBaseScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends ConsumerState<KnowledgeBaseScreen> {
  final _askController = TextEditingController();
  KbAnswer? _answer;
  bool _asking = false;
  String? _askError;

  @override
  void dispose() {
    _askController.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _askController.text.trim();
    if (q.isEmpty || _asking) return;
    setState(() {
      _asking = true;
      _askError = null;
      _answer = null;
    });
    try {
      final a = await kbAsk(q);
      if (mounted) setState(() => _answer = a);
    } catch (e) {
      if (mounted) setState(() => _askError = '$e');
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _addText() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddTextDialog(),
    );
    if (result == true) {
      ref.invalidate(kbChunksProvider);
      ref.invalidate(kbStatusProvider);
    }
  }

  Future<void> _addUrl() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddUrlDialog(),
    );
    if (result == true) {
      ref.invalidate(kbChunksProvider);
      ref.invalidate(kbStatusProvider);
    }
  }

  Future<void> _addFile() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const KbAddFileDialog(),
    );
    if (result == true) {
      ref.invalidate(kbChunksProvider);
      ref.invalidate(kbStatusProvider);
    }
  }

  Future<void> _crawlSite() async {
    final started = await showDialog<bool>(
      context: context,
      builder: (_) => const KbCrawlDialog(),
    );
    if (started == true) ref.invalidate(kbCrawlJobsProvider);
  }

  Future<void> _delete(KbChunk c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MikeeColors.cardTop,
        title: const Text('Delete this entry?', style: TextStyle(color: Colors.white)),
        content: Text(
          c.content.length > 160 ? '${c.content.substring(0, 160)}…' : c.content,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: MikeeColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await kbDeleteChunk(c.id);
      ref.invalidate(kbChunksProvider);
      ref.invalidate(kbStatusProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chunksAsync = ref.watch(kbChunksProvider);
    final statusAsync = ref.watch(kbStatusProvider);

    return Scaffold(
      backgroundColor: MikeeColors.background,
      appBar: AppBar(
        title: const Text('Knowledge Base'),
        backgroundColor: MikeeColors.surface,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(kbChunksProvider);
              ref.invalidate(kbStatusProvider);
            },
          ),
        ],
      ),
      floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
        FloatingActionButton.extended(
          heroTag: 'kb_crawl',
          backgroundColor: MikeeColors.inset,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.travel_explore),
          label: const Text('Crawl website'),
          onPressed: _crawlSite,
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'kb_add_url',
          backgroundColor: MikeeColors.inset,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.link),
          label: const Text('Add web page'),
          onPressed: _addUrl,
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'kb_add_file',
          backgroundColor: MikeeColors.inset,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.upload_file),
          label: const Text('Add document'),
          onPressed: _addFile,
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'kb_add_text',
          backgroundColor: MikeeColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.post_add),
          label: const Text('Add knowledge'),
          onPressed: _addText,
        ),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          statusAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => _statusBanner(
              color: MikeeColors.error,
              icon: Icons.cloud_off,
              text: 'Spine unreachable: $e',
            ),
            data: (s) => _statusRow(s),
          ),
          const SizedBox(height: 20),
          _askPanel(),
          KbCrawlJobsStrip(onJobFinished: () {
            ref.invalidate(kbChunksProvider);
            ref.invalidate(kbStatusProvider);
          }),
          const SizedBox(height: 24),
          Text('KNOWLEDGE ENTRIES',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          chunksAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to load: $e',
                  style: const TextStyle(color: Colors.white54)),
            ),
            data: (chunks) => chunks.isEmpty
                ? _emptyState()
                : Column(children: [for (final c in chunks) _chunkCard(c)]),
          ),
          const KbSourcesSection(),
          const SizedBox(height: 230), // clear the taller FAB stack
        ],
      ),
    );
  }

  Widget _statusRow(KbStatus s) {
    Widget chip(String label, bool ok) => Container(
          margin: const EdgeInsets.only(right: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: (ok ? MikeeColors.success : MikeeColors.warning).withOpacity(0.12),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
                color:
                    (ok ? MikeeColors.success : MikeeColors.warning).withOpacity(0.5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded,
                size: 14, color: ok ? MikeeColors.success : MikeeColors.warning),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: ok ? MikeeColors.success : MikeeColors.warning)),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(children: [
        chip('${s.chunks} entries · ${s.faqChunks} FAQ', s.chunks > 0),
        chip('Embeddings (Voyage)', s.embeddingsReady),
        chip('Answers (Claude)', s.llmReady),
        chip('Voice grounding (ElevenLabs)', s.voiceGroundingReady),
      ]),
      if (!s.ready)
        _statusBanner(
          color: MikeeColors.warning,
          icon: Icons.key_off,
          text:
              'Brain partly configured — set the missing API keys in spine/.env '
              '(see docs/KB_SETUP.md) to enable ingestion and grounded answers.',
        ),
    ]);
  }

  Widget _statusBanner(
      {required Color color, required IconData icon, required String text}) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child:
                Text(text, style: TextStyle(color: color, fontSize: 13, height: 1.3))),
      ]),
    );
  }

  Widget _askPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [MikeeColors.cardTop, MikeeColors.cardBottom]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MikeeColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.psychology_alt, color: MikeeColors.primary, size: 20),
          SizedBox(width: 8),
          Text('Try a question',
              style: TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          SizedBox(width: 8),
          Text('— same brain the robot speaks from',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _askController,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _ask(),
              decoration: InputDecoration(
                hintText: 'e.g. What are the office hours?',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: MikeeColors.inset,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: MikeeColors.border)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: MikeeColors.primary,
                  foregroundColor: Colors.white),
              onPressed: _asking ? null : _ask,
              icon: _asking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, size: 18),
              label: const Text('Ask'),
            ),
          ),
        ]),
        if (_askError != null) ...[
          const SizedBox(height: 12),
          Text(_askError!,
              style: const TextStyle(color: MikeeColors.error, fontSize: 13)),
        ],
        if (_answer != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: MikeeColors.inset,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MikeeColors.primary.withOpacity(0.35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_answer!.answer,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, height: 1.45)),
              const SizedBox(height: 10),
              Row(children: [
                _sourceChip(_answer!.source),
                if (_answer!.similarity != null) ...[
                  const SizedBox(width: 8),
                  Text('similarity ${_answer!.similarity!.toStringAsFixed(2)}',
                      style:
                          const TextStyle(color: Colors.white30, fontSize: 11)),
                ],
              ]),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _sourceChip(String source) {
    final (label, color) = switch (source) {
      'kb' => ('FAQ fast-path', MikeeColors.success),
      'claude' => ('Grounded answer (Claude)', MikeeColors.info),
      _ => ('Human handoff', MikeeColors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(36),
      alignment: Alignment.center,
      child: Column(children: [
        const Icon(Icons.menu_book, color: Colors.white24, size: 44),
        const SizedBox(height: 12),
        const Text('The knowledge base is empty.',
            style: TextStyle(color: Colors.white54, fontSize: 15)),
        const SizedBox(height: 6),
        Text(
          'Add company facts, FAQs, or a web page — Mini will answer '
          'visitors from this content only.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
        ),
      ]),
    );
  }

  Widget _chunkCard(KbChunk c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MikeeColors.cardTop,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MikeeColors.borderFaint),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (c.isFaq)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: MikeeColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text('FAQ',
                      style:
                          TextStyle(color: MikeeColors.success, fontSize: 10)),
                ),
              if (c.topic != null && c.topic!.isNotEmpty)
                Text(c.topic!,
                    style: const TextStyle(
                        color: MikeeColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
            ]),
            if (c.isFaq || (c.topic?.isNotEmpty ?? false))
              const SizedBox(height: 6),
            Text(c.content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.4)),
            if (c.source != null && c.source!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(c.source!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white30, fontSize: 11)),
            ],
          ]),
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
          onPressed: () => _delete(c),
        ),
      ]),
    );
  }
}

class _AddTextDialog extends StatefulWidget {
  const _AddTextDialog();

  @override
  State<_AddTextDialog> createState() => _AddTextDialogState();
}

class _AddTextDialogState extends State<_AddTextDialog> {
  final _topic = TextEditingController();
  final _text = TextEditingController();
  bool _isFaq = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _topic.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_text.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await kbIngestText(_text.text.trim(),
          topic: _topic.text.trim(), isFaq: _isFaq);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MikeeColors.cardTop,
      title: const Text('Add knowledge', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _topic,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Topic (optional) — e.g. Office hours'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            maxLines: 8,
            style: const TextStyle(color: Colors.white),
            decoration: _dec(
                'The knowledge itself — facts, an FAQ answer, a policy…\n'
                'Mini answers visitors from this text.'),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _isFaq,
            onChanged: _busy ? null : (v) => setState(() => _isFaq = v ?? false),
            title: const Text('FAQ (exact answer, spoken as-is when matched)',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: MikeeColors.primary,
            contentPadding: EdgeInsets.zero,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style:
                      const TextStyle(color: MikeeColors.error, fontSize: 12)),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: MikeeColors.primary,
              foregroundColor: Colors.white),
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Add'),
        ),
      ],
    );
  }
}

class _AddUrlDialog extends StatefulWidget {
  const _AddUrlDialog();

  @override
  State<_AddUrlDialog> createState() => _AddUrlDialogState();
}

class _AddUrlDialogState extends State<_AddUrlDialog> {
  final _topic = TextEditingController();
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _topic.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_url.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await kbIngestUrl(_url.text.trim(), topic: _topic.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MikeeColors.cardTop,
      title: const Text('Add a web page', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _url,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('https://… (public page — fetched and indexed)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _topic,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Topic (optional)'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style:
                      const TextStyle(color: MikeeColors.error, fontSize: 12)),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: MikeeColors.primary,
              foregroundColor: Colors.white),
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Fetch & add'),
        ),
      ],
    );
  }
}

InputDecoration _dec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24),
      filled: true,
      fillColor: MikeeColors.inset,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MikeeColors.border)),
    );
