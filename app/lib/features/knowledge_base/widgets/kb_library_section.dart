import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../providers/kb_provider.dart';

/// The Knowledge Base "library" — everything Mini can answer from, segregated
/// by how it got here instead of one flat 900-row scroll:
///
///  • Crawled sites   — a managed crawl (one card, drill into pages → chunks);
///                       carries the auto-sync controls (toggle / interval / sync).
///  • Web pages       — single-page sources (managed = re-syncable; legacy = delete-only).
///  • Manual entries  — hand-typed knowledge / FAQ (editable in place).
///  • Documents       — ingested files.
///
/// Chunk→source linkage comes from `source_id` (managed crawl/url) with a
/// URL/heuristic fallback for entries added before managed sources existed.
class KbLibrarySection extends ConsumerWidget {
  final VoidCallback onChanged; // refresh chunks + status after a mutation
  const KbLibrarySection({Key? key, required this.onChanged}) : super(key: key);

  static bool _looksLikeFile(String? s) {
    if (s == null || s.isEmpty) return false;
    final lower = s.toLowerCase();
    return lower.endsWith('.pdf') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.md');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chunksAsync = ref.watch(kbChunksProvider);
    final sourcesAsync = ref.watch(kbSyncSourcesProvider);

    return chunksAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Failed to load: $e', style: const TextStyle(color: Colors.white54)),
      ),
      data: (chunks) {
        final sources = sourcesAsync.value ?? const <KbSyncSource>[];
        final crawlSources = sources.where((s) => s.kind == 'crawl').toList();
        final urlSources = sources.where((s) => s.kind == 'url').toList();
        final managedIds = sources.map((s) => s.id).toSet();

        // Partition chunks: managed (by source_id) vs everything else.
        final bySourceId = <String, List<KbChunk>>{};
        final unmanaged = <KbChunk>[];
        for (final c in chunks) {
          final sid = c.sourceId;
          if (sid != null && managedIds.contains(sid)) {
            bySourceId.putIfAbsent(sid, () => []).add(c);
          } else {
            unmanaged.add(c);
          }
        }
        final legacyUrl = unmanaged.where((c) => c.sourceIsUrl).toList();
        final docChunks =
            unmanaged.where((c) => !c.sourceIsUrl && _looksLikeFile(c.source)).toList();
        final manual =
            unmanaged.where((c) => !c.sourceIsUrl && !_looksLikeFile(c.source)).toList();

        final legacyGroups = _groupBySource(legacyUrl);
        final docGroups = _groupBySource(docChunks);

        final lastSynced = sources
            .map((s) => s.lastSyncedAt)
            .whereType<String>()
            .fold<String?>(null, (a, b) => (a == null || b.compareTo(a) > 0) ? b : a);

        final pageCount = urlSources.length + legacyGroups.length;

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SummaryStrip(
            entries: chunks.length,
            crawls: crawlSources.length,
            pages: pageCount,
            manual: manual.length,
            docs: docGroups.length,
            faqs: chunks.where((c) => c.isFaq).length,
            lastSynced: lastSynced,
          ),
          const SizedBox(height: 16),

          _CollapsibleGroup(
            icon: Icons.travel_explore,
            title: 'Crawled sites',
            count: crawlSources.length,
            initiallyExpanded: true,
            emptyHint: 'Crawl a website (button below) to add one.',
            children: [
              for (final s in crawlSources)
                _CrawlSourceCard(
                    source: s, chunks: bySourceId[s.id] ?? const [], onChanged: onChanged),
            ],
          ),

          _CollapsibleGroup(
            icon: Icons.link,
            title: 'Web pages',
            count: pageCount,
            emptyHint: 'Add a single web page with "Add web page".',
            children: [
              for (final s in urlSources)
                _UrlSourceCard(
                    source: s, chunks: bySourceId[s.id] ?? const [], onChanged: onChanged),
              for (final entry in legacyGroups.entries)
                _LegacyGroupCard(
                    label: entry.key,
                    chunks: entry.value,
                    icon: Icons.link,
                    onChanged: onChanged),
            ],
          ),

          _CollapsibleGroup(
            icon: Icons.edit_note,
            title: 'Manual entries',
            count: manual.length,
            emptyHint: 'Add facts or FAQs with "Add knowledge".',
            children: [
              for (final c in manual) _ManualEntryRow(chunk: c, onChanged: onChanged),
            ],
          ),

          if (docGroups.isNotEmpty)
            _CollapsibleGroup(
              icon: Icons.description,
              title: 'Documents',
              count: docGroups.length,
              children: [
                for (final entry in docGroups.entries)
                  _LegacyGroupCard(
                      label: entry.key,
                      chunks: entry.value,
                      icon: Icons.description,
                      onChanged: onChanged),
              ],
            ),
        ]);
      },
    );
  }

  static Map<String, List<KbChunk>> _groupBySource(List<KbChunk> chunks) {
    final m = <String, List<KbChunk>>{};
    for (final c in chunks) {
      m.putIfAbsent(c.source ?? '(unknown)', () => []).add(c);
    }
    return m;
  }
}

// ─────────────────────────────────────────────────────────── summary strip ──

class _SummaryStrip extends StatelessWidget {
  final int entries, crawls, pages, manual, docs, faqs;
  final String? lastSynced;
  const _SummaryStrip({
    required this.entries,
    required this.crawls,
    required this.pages,
    required this.manual,
    required this.docs,
    required this.faqs,
    required this.lastSynced,
  });

  @override
  Widget build(BuildContext context) {
    String synced = 'never';
    if (lastSynced != null) {
      final d = DateTime.tryParse(lastSynced!)?.toLocal();
      if (d != null) {
        const mon = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        synced = '${d.day} ${mon[d.month - 1]}';
      }
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _stat('$entries', 'entries', MikeeColors.primary),
      _stat('$crawls', 'crawls', Colors.white70),
      _stat('$pages', 'web pages', Colors.white70),
      _stat('$manual', 'manual', Colors.white70),
      if (docs > 0) _stat('$docs', 'documents', Colors.white70),
      if (faqs > 0) _stat('$faqs', 'FAQ', MikeeColors.success),
      _stat(synced, 'last synced', MikeeColors.info),
    ]);
  }

  Widget _stat(String value, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: MikeeColors.cardTop,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MikeeColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(value,
              style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ]),
      );
}

// ────────────────────────────────────────────────────── collapsible group ──

class _CollapsibleGroup extends StatefulWidget {
  final IconData icon;
  final String title;
  final int count;
  final List<Widget> children;
  final bool initiallyExpanded;
  final String? emptyHint;
  const _CollapsibleGroup({
    required this.icon,
    required this.title,
    required this.count,
    required this.children,
    this.initiallyExpanded = false,
    this.emptyHint,
  });

  @override
  State<_CollapsibleGroup> createState() => _CollapsibleGroupState();
}

class _CollapsibleGroupState extends State<_CollapsibleGroup> {
  late bool _open = widget.initiallyExpanded && widget.count > 0;

  @override
  Widget build(BuildContext context) {
    final empty = widget.count == 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: MikeeColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MikeeColors.border),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: empty ? null : () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(widget.icon, size: 18, color: MikeeColors.primary),
              const SizedBox(width: 10),
              Text(widget.title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: MikeeColors.inset,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('${widget.count}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ),
              const Spacer(),
              if (!empty)
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white38, size: 20),
            ]),
          ),
        ),
        if (_open && !empty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(children: widget.children),
          ),
        if (empty && widget.emptyHint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 0, 14, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.emptyHint!,
                  style: const TextStyle(color: Colors.white24, fontSize: 12)),
            ),
          ),
      ]),
    );
  }
}

/// Shared busy/refresh/error-snackbar runner for the interactive rows below.
mixin _RowActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;
  VoidCallback get onChangedCb;

  Future<void> run(Future<void> Function() op, {String? toast}) async {
    setState(() => busy = true);
    try {
      await op();
      if (!mounted) return;
      ref.invalidate(kbSyncSourcesProvider);
      onChangedCb();
      if (toast != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(toast), backgroundColor: MikeeColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: MikeeColors.error));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

// ──────────────────────────────────────────────────────── crawled site card ──

class _CrawlSourceCard extends ConsumerStatefulWidget {
  final KbSyncSource source;
  final List<KbChunk> chunks;
  final VoidCallback onChanged;
  const _CrawlSourceCard(
      {required this.source, required this.chunks, required this.onChanged});

  @override
  ConsumerState<_CrawlSourceCard> createState() => _CrawlSourceCardState();
}

class _CrawlSourceCardState extends ConsumerState<_CrawlSourceCard>
    with _RowActions<_CrawlSourceCard> {
  bool _showPages = false;
  static const _intervals = <String, int>{'6h': 6, 'Daily': 24, 'Weekly': 168};
  @override
  VoidCallback get onChangedCb => widget.onChanged;

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final pages = KbLibrarySection._groupBySource(widget.chunks);
    return _cardShell(children: [
      Row(children: [
        Expanded(
          child: Text(s.url,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
        _statusText(s),
      ]),
      const SizedBox(height: 6),
      Text('${s.chunkCount} chunks · ${pages.length} pages',
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
      const SizedBox(height: 10),
      Row(children: [
        for (final e in _intervals.entries) ...[
          _MiniChip(
            label: e.key,
            active: s.autoSync && s.syncIntervalHours == e.value,
            enabled: !busy,
            onTap: () => run(() =>
                kbSourceSetSync(s.id, autoSync: true, intervalHours: e.value)),
          ),
          const SizedBox(width: 6),
        ],
        const Spacer(),
        const Text('Auto', style: TextStyle(color: Colors.white38, fontSize: 12)),
        Switch(
          value: s.autoSync,
          activeColor: MikeeColors.primary,
          onChanged: busy ? null : (v) => run(() => kbSourceSetSync(s.id, autoSync: v)),
        ),
      ]),
      const Divider(height: 18, color: MikeeColors.border),
      Row(children: [
        _action(Icons.travel_explore, _showPages ? 'Hide pages' : 'View pages',
            () => setState(() => _showPages = !_showPages)),
        const Spacer(),
        if (busy)
          const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        else ...[
          _action(Icons.refresh, 'Re-sync',
              () => run(() => kbSourceSyncNow(s.id), toast: 'Re-synced ${s.url}')),
          const SizedBox(width: 4),
          _action(Icons.delete_outline, 'Delete', () => _confirmDelete(s), danger: true),
        ],
      ]),
      if (_showPages) ...[
        const SizedBox(height: 8),
        for (final entry in (pages.entries.toList()
              ..sort((a, b) => b.value.length.compareTo(a.value.length))))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              const Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.white24),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_shortPath(entry.key),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ),
              Text('${entry.value.length}',
                  style: const TextStyle(color: Colors.white30, fontSize: 12)),
            ]),
          ),
      ],
    ]);
  }

  Future<void> _confirmDelete(KbSyncSource s) async {
    final ok = await _confirm(context, 'Delete this crawled site?',
        '${s.url}\n\nRemoves all ${s.chunkCount} chunks and stops auto-sync.');
    if (ok) run(() => kbSyncSourceDelete(s.id), toast: 'Deleted ${s.url}');
  }
}

// ─────────────────────────────────────────────────── managed single-URL card ──

class _UrlSourceCard extends ConsumerStatefulWidget {
  final KbSyncSource source;
  final List<KbChunk> chunks;
  final VoidCallback onChanged;
  const _UrlSourceCard(
      {required this.source, required this.chunks, required this.onChanged});

  @override
  ConsumerState<_UrlSourceCard> createState() => _UrlSourceCardState();
}

class _UrlSourceCardState extends ConsumerState<_UrlSourceCard>
    with _RowActions<_UrlSourceCard> {
  @override
  VoidCallback get onChangedCb => widget.onChanged;

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    return _cardShell(children: [
      Row(children: [
        Expanded(
          child: Text(s.url,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
        _statusText(s),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Text('${s.chunkCount} chunks',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const Spacer(),
        if (busy)
          const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        else ...[
          _action(Icons.refresh, 'Re-sync',
              () => run(() => kbSourceSyncNow(s.id), toast: 'Re-synced ${s.url}')),
          const SizedBox(width: 4),
          _action(Icons.delete_outline, 'Delete', () async {
            final ok = await _confirm(context, 'Delete this web page?',
                '${s.url}\n\nRemoves its ${s.chunkCount} chunks.');
            if (ok) run(() => kbSyncSourceDelete(s.id), toast: 'Deleted ${s.url}');
          }, danger: true),
        ],
      ]),
    ]);
  }
}

// ──────────────────────────────────────── legacy web-page / document group ──

class _LegacyGroupCard extends ConsumerStatefulWidget {
  final String label;
  final List<KbChunk> chunks;
  final IconData icon;
  final VoidCallback onChanged;
  const _LegacyGroupCard(
      {required this.label,
      required this.chunks,
      required this.icon,
      required this.onChanged});

  @override
  ConsumerState<_LegacyGroupCard> createState() => _LegacyGroupCardState();
}

class _LegacyGroupCardState extends ConsumerState<_LegacyGroupCard>
    with _RowActions<_LegacyGroupCard> {
  @override
  VoidCallback get onChangedCb => widget.onChanged;

  @override
  Widget build(BuildContext context) {
    return _cardShell(children: [
      Row(children: [
        Expanded(
          child: Text(_shortPath(widget.label),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
        const SizedBox(width: 8),
        Text('${widget.chunks.length} chunks',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(width: 8),
        if (busy)
          const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        else
          _action(Icons.delete_outline, 'Delete', () async {
            final ok = await _confirm(context, 'Delete this entry?',
                '${widget.label}\n\nRemoves its ${widget.chunks.length} chunks.');
            if (ok) {
              run(() => kbDeleteChunks(widget.chunks.map((c) => c.id).toList()),
                  toast: 'Deleted ${_shortPath(widget.label)}');
            }
          }, danger: true),
      ]),
    ]);
  }
}

// ───────────────────────────────────────────────────────── manual entry row ──

class _ManualEntryRow extends ConsumerStatefulWidget {
  final KbChunk chunk;
  final VoidCallback onChanged;
  const _ManualEntryRow({required this.chunk, required this.onChanged});

  @override
  ConsumerState<_ManualEntryRow> createState() => _ManualEntryRowState();
}

class _ManualEntryRowState extends ConsumerState<_ManualEntryRow>
    with _RowActions<_ManualEntryRow> {
  @override
  VoidCallback get onChangedCb => widget.onChanged;

  @override
  Widget build(BuildContext context) {
    final c = widget.chunk;
    return _cardShell(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (c.isFaq)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: MikeeColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text('FAQ',
                      style: TextStyle(color: MikeeColors.success, fontSize: 10)),
                ),
              if (c.topic != null && c.topic!.isNotEmpty)
                Flexible(
                  child: Text(c.topic!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: MikeeColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
            ]),
            if (c.isFaq || (c.topic?.isNotEmpty ?? false)) const SizedBox(height: 6),
            Text(c.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
          ]),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          _action(Icons.edit_outlined, 'Edit', _edit),
          const SizedBox(width: 4),
          _action(Icons.delete_outline, 'Delete', () async {
            final ok = await _confirm(context, 'Delete this entry?',
                c.content.length > 160 ? '${c.content.substring(0, 160)}…' : c.content);
            if (ok) run(() => kbDeleteChunk(c.id), toast: 'Deleted');
          }, danger: true),
        ],
      ]),
    ]);
  }

  Future<void> _edit() async {
    final c = widget.chunk;
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _EditEntryDialog(
          initialText: c.content, initialTopic: c.topic ?? '', initialFaq: c.isFaq),
    );
    if (result == null) return;
    run(
      () => kbUpdateManualEntry(c.id, result.text,
          topic: result.topic, isFaq: result.isFaq),
      toast: 'Updated',
    );
  }
}

class _EditResult {
  final String text;
  final String topic;
  final bool isFaq;
  _EditResult(this.text, this.topic, this.isFaq);
}

class _EditEntryDialog extends StatefulWidget {
  final String initialText, initialTopic;
  final bool initialFaq;
  const _EditEntryDialog(
      {required this.initialText,
      required this.initialTopic,
      required this.initialFaq});

  @override
  State<_EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<_EditEntryDialog> {
  late final _topic = TextEditingController(text: widget.initialTopic);
  late final _text = TextEditingController(text: widget.initialText);
  late bool _isFaq = widget.initialFaq;

  @override
  void dispose() {
    _topic.dispose();
    _text.dispose();
    super.dispose();
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
      title: const Text('Edit knowledge', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _topic,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Topic (optional)')),
          const SizedBox(height: 12),
          TextField(
              controller: _text,
              maxLines: 8,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('The knowledge itself')),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _isFaq,
            onChanged: (v) => setState(() => _isFaq = v ?? false),
            title: const Text('FAQ (exact answer, spoken as-is when matched)',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: MikeeColors.primary,
            contentPadding: EdgeInsets.zero,
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Saving re-embeds the entry (old version is replaced).',
                style: TextStyle(color: Colors.white24, fontSize: 11)),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: MikeeColors.primary, foregroundColor: Colors.white),
          onPressed: () {
            if (_text.text.trim().isEmpty) return;
            Navigator.pop(context,
                _EditResult(_text.text.trim(), _topic.text.trim(), _isFaq));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────── helpers ──

Widget _cardShell({required List<Widget> children}) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: MikeeColors.cardTop,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MikeeColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );

Widget _statusText(KbSyncSource s) {
  final color = s.lastStatus == 'error'
      ? MikeeColors.error
      : s.lastStatus == 'ok'
          ? MikeeColors.success
          : MikeeColors.textMuted;
  String label;
  if (s.lastStatus == 'error') {
    label = 'sync failed';
  } else if (s.lastSyncedAt == null) {
    label = 'not synced';
  } else {
    final d = DateTime.tryParse(s.lastSyncedAt!)?.toLocal();
    label = d == null ? 'synced' : 'synced ${d.day}/${d.month}';
  }
  return Text(label, style: TextStyle(color: color, fontSize: 11));
}

Widget _action(IconData icon, String label, VoidCallback onTap, {bool danger = false}) {
  final color = danger ? MikeeColors.error : Colors.white60;
  return TextButton.icon(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: Icon(icon, size: 16, color: color),
    label: Text(label, style: TextStyle(fontSize: 12, color: color)),
  );
}

String _shortPath(String url) {
  var u = url.replaceFirst(RegExp(r'^https?://'), '');
  if (u.endsWith('/')) u = u.substring(0, u.length - 1);
  return u.isEmpty ? url : u;
}

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: MikeeColors.cardTop,
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Text(body, style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete', style: TextStyle(color: MikeeColors.error)),
        ),
      ],
    ),
  );
  return ok == true;
}

class _MiniChip extends StatelessWidget {
  final String label;
  final bool active, enabled;
  final VoidCallback onTap;
  const _MiniChip(
      {required this.label,
      required this.active,
      required this.enabled,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? MikeeColors.primary : MikeeColors.inset,
          border: Border.all(color: active ? MikeeColors.primary : MikeeColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: active ? Colors.white : Colors.white54)),
      ),
    );
  }
}
