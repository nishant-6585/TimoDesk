import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../staff/providers/staff_list_provider.dart';
import '../providers/snapshot_list_provider.dart';
import '../providers/recordings_provider.dart';

/// Gallery — two tabs: remote snapshots (F7, admin-captured photos from the
/// robot camera) and enrolled staff faces. Both read the spine over HTTP and
/// render private images via short-lived signed URLs.
class GalleryScreen extends ConsumerWidget {
  /// Optional capture id from the `/gallery/:captureId` deep-link (unused for now).
  final String? captureId;
  const GalleryScreen({Key? key, this.captureId}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(children: [
                Icon(Icons.photo_library_rounded, size: 28, color: MikeeColors.primary),
                const SizedBox(width: 12),
                Text('Gallery', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold)),
              ]),
            ),
            TabBar(
              isScrollable: true,
              indicatorColor: MikeeColors.primary,
              labelColor: MikeeColors.textPrimary,
              unselectedLabelColor: MikeeColors.textSecondary,
              labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Snapshots'),
                Tab(text: 'Recordings'),
                Tab(text: 'Staff'),
              ],
            ),
            const Expanded(
              child: TabBarView(
                  children: [_SnapshotsTab(), _RecordingsTab(), _StaffTab()]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Remote snapshots captured by an admin from the robot camera (F7).
class _SnapshotsTab extends ConsumerWidget {
  const _SnapshotsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapsAsync = ref.watch(snapshotListProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(snapshotListProvider),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: snapsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _GalleryMessage(
            icon: Icons.cloud_off_rounded,
            title: 'Failed to load snapshots',
            detail: '$e',
            onRetry: () => ref.invalidate(snapshotListProvider),
          ),
          data: (snaps) {
            if (snaps.isEmpty) {
              return const _GalleryMessage(
                icon: Icons.photo_camera_outlined,
                title: 'No snapshots yet',
                detail: 'Tap Snapshot on the Control screen to capture a photo from the robot.',
              );
            }
            return GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.85,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final s in snaps) _SnapshotTile(snapshot: s)],
            );
          },
        ),
      ),
    );
  }
}

/// Recorded video clips (Record button on the dashboard → ffmpeg on spine).
/// Plays in the browser's native player; also downloadable.
class _RecordingsTab extends ConsumerWidget {
  const _RecordingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recsAsync = ref.watch(recordingsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(recordingsProvider),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: recsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _GalleryMessage(
            icon: Icons.cloud_off_rounded,
            title: 'Failed to load recordings',
            detail: '$e',
            onRetry: () => ref.invalidate(recordingsProvider),
          ),
          data: (recs) {
            if (recs.isEmpty) {
              return const _GalleryMessage(
                icon: Icons.videocam_off_outlined,
                title: 'No recordings yet',
                detail: 'Tap Record on the dashboard to capture a clip from the '
                    'robot camera, then Stop to finalize it.',
              );
            }
            return Column(children: [for (final r in recs) _RecordingRow(rec: r)]);
          },
        ),
      ),
    );
  }
}

class _RecordingRow extends ConsumerWidget {
  final Recording rec;
  const _RecordingRow({required this.rec});

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MikeeColors.cardTop,
        title: const Text('Delete recording?', style: TextStyle(color: Colors.white)),
        content: Text(rec.file, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: MikeeColors.error))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await deleteRecording(rec.file);
      ref.invalidate(recordingsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  String _when() {
    if (rec.mtime <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(rec.mtime.toInt()).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MikeeColors.cardTop,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MikeeColors.border),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: MikeeColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.movie_rounded, color: MikeeColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rec.file,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w600, color: MikeeColors.textPrimary)),
            const SizedBox(height: 3),
            Text('${_when()}  ·  ${rec.sizeLabel}',
                style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textSecondary)),
          ]),
        ),
        _RecBtn(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          primary: true,
          onTap: () => launchUrl(Uri.parse(rec.url),
              mode: LaunchMode.externalApplication),
        ),
        const SizedBox(width: 8),
        _RecBtn(
          icon: Icons.download_rounded,
          label: 'Download',
          primary: false,
          onTap: () => launchUrl(Uri.parse(rec.url),
              mode: LaunchMode.externalApplication),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline_rounded,
              color: Colors.white38, size: 20),
          onPressed: () => _delete(context, ref),
        ),
      ]),
    );
  }
}

class _RecBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _RecBtn(
      {required this.icon,
      required this.label,
      required this.primary,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: primary ? MikeeColors.primary : MikeeColors.inset,
          borderRadius: BorderRadius.circular(8),
          border: primary ? null : Border.all(color: MikeeColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: primary ? Colors.white : MikeeColors.textSecondary),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primary ? Colors.white : MikeeColors.textSecondary)),
        ]),
      ),
    );
  }
}

/// Enrolled staff faces (unchanged — the original gallery, now a tab).
class _StaffTab extends ConsumerWidget {
  const _StaffTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffListProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(staffListProvider),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: staffAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _GalleryMessage(
            icon: Icons.cloud_off_rounded,
            title: 'Failed to load staff',
            detail: '$e',
            onRetry: () => ref.invalidate(staffListProvider),
          ),
          data: (staff) {
            if (staff.isEmpty) {
              return const _GalleryMessage(
                icon: Icons.people_outline_rounded,
                title: 'No staff enrolled yet',
                detail: 'Enroll staff to see their faces here.',
              );
            }
            return GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.85,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final m in staff) _FaceTile(member: m)],
            );
          },
        ),
      ),
    );
  }
}

/// One admin snapshot — the image, when it was taken, and who took it.
class _SnapshotTile extends ConsumerWidget {
  final Snapshot snapshot;
  const _SnapshotTile({required this.snapshot});

  String _when(DateTime? t) {
    if (t == null) return 'Unknown time';
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MikeeColors.cardTop,
        title: const Text('Delete snapshot?', style: TextStyle(color: Colors.white)),
        content: Text(_when(snapshot.takenAt), style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: MikeeColors.error))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await deleteSnapshot(snapshot.id);
      ref.invalidate(snapshotListProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = snapshot.imageUrl;
    final hasImage = url != null && url.isNotEmpty;

    final placeholder = Container(
      color: MikeeColors.primary.withValues(alpha: 0.10),
      alignment: Alignment.center,
      child: Icon(Icons.image_not_supported_outlined, size: 34, color: MikeeColors.textMuted),
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            hasImage
                ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder)
                : placeholder,
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _delete(context, ref),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _when(snapshot.takenAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: MikeeColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.person_outline_rounded, size: 12, color: MikeeColors.textMuted),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  snapshot.actor ?? 'autonomous',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textSecondary),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// One staff face — photo when available, colored initials otherwise.
class _FaceTile extends StatelessWidget {
  final StaffMember member;
  const _FaceTile({required this.member});

  static const _palette = [
    Color(0xFF6366F1), Color(0xFFEC4899), Color(0xFF14B8A6),
    Color(0xFFF59E0B), Color(0xFF10B981), Color(0xFF8B5CF6),
    Color(0xFFEF4444), Color(0xFF3B82F6), Color(0xFFFF6B35),
  ];

  @override
  Widget build(BuildContext context) {
    final name = member.fullName;
    final color = name.isEmpty ? _palette[0] : _palette[name.codeUnitAt(0) % _palette.length];
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();
    final url = member.photoUrl;
    final hasPhoto = url != null && url.isNotEmpty;

    final placeholder = Container(
      color: color.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: GoogleFonts.inter(color: color, fontSize: 34, fontWeight: FontWeight.w800),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: hasPhoto
              ? Image.network(
                  url,
                  fit: BoxFit.cover,
                  // Fall back to initials if the signed URL fails / expires.
                  errorBuilder: (_, __, ___) => placeholder,
                )
              : placeholder,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              name.isEmpty ? '—' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: MikeeColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Row(children: [
              if (member.personType != null) ...[
                _Badge(member.personType!, MikeeColors.primary),
                const SizedBox(width: 6),
              ],
              Icon(Icons.face_rounded, size: 12,
                  color: member.embeddingCount > 0 ? MikeeColors.success : MikeeColors.textMuted),
              const SizedBox(width: 3),
              Text('${member.embeddingCount}',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: member.embeddingCount > 0 ? MikeeColors.success : MikeeColors.textMuted)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _GalleryMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onRetry;
  const _GalleryMessage({required this.icon, required this.title, required this.detail, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: MikeeColors.textMuted),
          const SizedBox(height: 16),
          Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: MikeeColors.textSecondary)),
          const SizedBox(height: 6),
          Text(detail, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textMuted)),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 16), label: const Text('Retry')),
          ],
        ]),
      ),
    );
  }
}
