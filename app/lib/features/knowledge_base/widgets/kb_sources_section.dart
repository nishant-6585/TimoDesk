import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../providers/kb_provider.dart';

/// Crawl-job progress strip. Polls while any job is running so the admin sees
/// pages/chunks tick up; silent (renders nothing) when there are no jobs.
class KbCrawlJobsStrip extends ConsumerStatefulWidget {
  /// Called when a running job finishes — lets the screen refresh the entries.
  final VoidCallback onJobFinished;
  const KbCrawlJobsStrip({Key? key, required this.onJobFinished}) : super(key: key);

  @override
  ConsumerState<KbCrawlJobsStrip> createState() => _KbCrawlJobsStripState();
}

class _KbCrawlJobsStripState extends ConsumerState<KbCrawlJobsStrip> {
  Timer? _poll;
  bool _wasRunning = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _syncPolling(List<KbCrawlJob> jobs) {
    final running = jobs.any((j) => j.running);
    if (running && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 2), (_) {
        ref.invalidate(kbCrawlJobsProvider);
      });
    } else if (!running && _poll != null) {
      _poll?.cancel();
      _poll = null;
    }
    if (_wasRunning && !running) widget.onJobFinished();
    _wasRunning = running;
  }

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(kbCrawlJobsProvider);
    return jobsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(), // strip is best-effort chrome
      data: (jobs) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncPolling(jobs);
        });
        if (jobs.isEmpty) return const SizedBox.shrink();
        final show = jobs.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text('CRAWL JOBS',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            for (final j in show) _jobRow(j),
          ],
        );
      },
    );
  }

  Widget _jobRow(KbCrawlJob j) {
    final color = j.running
        ? MikeeColors.info
        : j.status == 'error'
            ? MikeeColors.error
            : MikeeColors.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MikeeColors.cardTop,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MikeeColors.border),
      ),
      child: Row(children: [
        if (j.running)
          const SizedBox(
              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
        else
          Icon(j.status == 'error' ? Icons.error_outline : Icons.check_circle,
              size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(j.seedUrl,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        Text(
          '${j.pagesCrawled}/${j.maxPages} pages · ${j.chunks} chunks'
          '${j.errors.isNotEmpty ? ' · ${j.errors.length} errors' : ''}',
          style: TextStyle(color: color, fontSize: 12),
        ),
      ]),
    );
  }
}

/// External ("3rd-party") knowledge sources — asked ONLY after a local-KB miss,
/// in priority order. Configure any HTTP KB endpoint (ElevenLabs webhook, a
/// corporate FAQ service, another site's KB…).
class KbSourcesSection extends ConsumerWidget {
  const KbSourcesSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(kbSourcesProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 24),
      Row(children: [
        Expanded(
          child: Text('EXTERNAL KNOWLEDGE SOURCES — asked after local KB',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
        ),
        TextButton.icon(
          onPressed: () => _add(context, ref),
          icon: const Icon(Icons.add, size: 16, color: MikeeColors.primary),
          label: const Text('Add source',
              style: TextStyle(color: MikeeColors.primary, fontSize: 13)),
        ),
      ]),
      const SizedBox(height: 8),
      sourcesAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (e, _) => Text('Could not load sources: $e',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        data: (sources) => sources.isEmpty
            ? const Text(
                'None configured — Timo answers from the local KB only. Add an HTTP '
                'source (POST {question} → {answer}) to consult it when the local KB '
                'has no match.',
                style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4))
            : Column(children: [for (final s in sources) _SourceRow(source: s)]),
      ),
    ]);
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final added = await showDialog<bool>(
        context: context, builder: (_) => const _AddSourceDialog());
    if (added == true) ref.invalidate(kbSourcesProvider);
  }
}

class _SourceRow extends ConsumerStatefulWidget {
  final KbSource source;
  const _SourceRow({required this.source});

  @override
  ConsumerState<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends ConsumerState<_SourceRow> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() op) async {
    setState(() => _busy = true);
    try {
      await op();
      ref.invalidate(kbSourcesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: MikeeColors.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: MikeeColors.cardTop,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MikeeColors.border),
      ),
      child: Row(children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: MikeeColors.inset,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: MikeeColors.border),
          ),
          child: Center(
            child: Text('${s.priority}',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            Text(s.url,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
        ),
        if (_busy)
          const SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        else ...[
          IconButton(
            tooltip: 'Higher priority (asked earlier)',
            icon: const Icon(Icons.arrow_upward, size: 16, color: Colors.white38),
            onPressed: s.priority <= 0
                ? null
                : () => _run(() => kbSourceUpdate(s.name, priority: s.priority - 1)),
          ),
          IconButton(
            tooltip: 'Lower priority',
            icon: const Icon(Icons.arrow_downward, size: 16, color: Colors.white38),
            onPressed: () => _run(() => kbSourceUpdate(s.name, priority: s.priority + 1)),
          ),
          Switch(
            value: s.enabled,
            activeColor: MikeeColors.primary,
            onChanged: (v) => _run(() => kbSourceUpdate(s.name, enabled: v)),
          ),
          IconButton(
            tooltip: 'Remove source',
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white38),
            onPressed: () => _run(() => kbSourceRemove(s.name)),
          ),
        ],
      ]),
    );
  }
}

class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog();

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;
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
    if (_name.text.trim().isEmpty || _url.text.trim().isEmpty) {
      setState(() => _error = 'Name and URL are required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await kbSourceAdd(
        name: _name.text.trim(),
        url: _url.text.trim(),
        authorizationToken: _token.text.trim(),
        description: _description.text.trim(),
      );
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

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: MikeeColors.inset,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: MikeeColors.border)),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MikeeColors.cardTop,
      title: const Text('Add knowledge source', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _name,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Name — e.g. hq-faq, elevenlabs')),
          const SizedBox(height: 12),
          TextField(
              controller: _url,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Endpoint URL — POST {question} → {answer}')),
          const SizedBox(height: 12),
          TextField(
              controller: _token,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Bearer token (optional — stored on the spine)')),
          const SizedBox(height: 12),
          TextField(
              controller: _description,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Description (optional)')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(color: MikeeColors.error, fontSize: 12)),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: MikeeColors.primary, foregroundColor: Colors.white),
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Add'),
        ),
      ],
    );
  }
}
