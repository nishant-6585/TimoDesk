import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../providers/kb_provider.dart';

/// Managed KB content sources (added URLs + website crawls) that can be
/// refreshed on demand ("Sync now") or auto-synced periodically. A re-sync
/// replaces the source's chunks (no duplicates). Auto-sync runs only when the
/// spine has KB_AUTOSYNC set; the per-source toggle here decides which sources
/// participate and how often.
class KbAutoSyncSection extends ConsumerWidget {
  const KbAutoSyncSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(kbSyncSourcesProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 24),
      Text('AUTO-SYNC SOURCES — URLs & crawls kept fresh',
          style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2)),
      const SizedBox(height: 8),
      async.when(
        loading: () => const SizedBox.shrink(),
        error: (e, _) => Text('Could not load sources: $e',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        data: (sources) => sources.isEmpty
            ? const Text(
                'No web sources yet. When you add a web page or crawl a website '
                'above, it appears here — turn on auto-sync to keep it fresh, or '
                'hit "Sync now" any time.',
                style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4))
            : Column(children: [for (final s in sources) _SyncSourceRow(source: s)]),
      ),
    ]);
  }
}

class _SyncSourceRow extends ConsumerStatefulWidget {
  final KbSyncSource source;
  const _SyncSourceRow({required this.source});

  @override
  ConsumerState<_SyncSourceRow> createState() => _SyncSourceRowState();
}

class _SyncSourceRowState extends ConsumerState<_SyncSourceRow> {
  bool _busy = false;

  /// Interval presets (hours). Matches the app's "pick one of N" chip idiom.
  static const _intervals = <String, int>{'6h': 6, 'Daily': 24, 'Weekly': 168};

  Future<void> _run(Future<void> Function() op, {String? toast}) async {
    setState(() => _busy = true);
    try {
      await op();
      if (!mounted) return;
      ref.invalidate(kbSyncSourcesProvider);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  String _synced(KbSyncSource s) {
    if (s.lastStatus == 'error') return 'last sync failed';
    if (s.lastSyncedAt == null) return 'never synced';
    final d = DateTime.tryParse(s.lastSyncedAt!)?.toLocal();
    if (d == null) return 'synced';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'synced ${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final statusColor = s.lastStatus == 'error'
        ? MikeeColors.error
        : s.lastStatus == 'ok'
            ? MikeeColors.success
            : MikeeColors.textMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MikeeColors.cardTop,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MikeeColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Line 1: kind + url + freshness/status.
        Row(children: [
          Icon(s.kind == 'crawl' ? Icons.travel_explore : Icons.link,
              size: 16, color: Colors.white54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(s.url,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Text('${_synced(s)} · ${s.chunkCount} chunks',
              style: TextStyle(color: statusColor, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        // Line 2: interval chips + auto-sync toggle + actions.
        Row(children: [
          for (final e in _intervals.entries) ...[
            _IntervalChip(
              label: e.key,
              active: s.autoSync && s.syncIntervalHours == e.value,
              enabled: !_busy,
              onTap: () => _run(() =>
                  kbSourceSetSync(s.id, autoSync: true, intervalHours: e.value)),
            ),
            const SizedBox(width: 6),
          ],
          const Spacer(),
          const Text('Auto', style: TextStyle(color: Colors.white38, fontSize: 12)),
          Switch(
            value: s.autoSync,
            activeColor: MikeeColors.primary,
            onChanged: _busy ? null : (v) => _run(() => kbSourceSetSync(s.id, autoSync: v)),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            IconButton(
              tooltip: 'Sync now',
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white54),
              onPressed: () => _run(() => kbSourceSyncNow(s.id), toast: 'Synced ${s.url}'),
            ),
            IconButton(
              tooltip: 'Remove source (deletes its chunks)',
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white38),
              onPressed: () => _run(() => kbSyncSourceDelete(s.id)),
            ),
          ],
        ]),
      ]),
    );
  }
}

/// One-of-N interval selector chip (matches the app's _SpeedChip/_EngineChip idiom).
class _IntervalChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  const _IntervalChip(
      {required this.label, required this.active, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
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
      ),
    );
  }
}
