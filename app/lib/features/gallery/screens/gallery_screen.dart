import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  /// Optional capture to deep-link to, from the `/gallery/:captureId` route.
  final String? captureId;
  const GalleryScreen({Key? key, this.captureId}) : super(key: key);

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  String _filter = 'All';
  int _snapshots = 12;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.image, size: 28, color: MikeeColors.primary), const SizedBox(width: 12), Text('Gallery', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold))]),
                const SizedBox(height: 4),
                Text('$_snapshots snapshots captured', style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
              ]),
            ]),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                _FilterChip('All', _filter == 'All', () => setState(() => _filter = 'All')),
                const SizedBox(width: 8),
                _FilterChip('Manual', _filter == 'Manual', () => setState(() => _filter = 'Manual')),
                const SizedBox(width: 8),
                _FilterChip('Face', _filter == 'Face', () => setState(() => _filter = 'Face')),
                const SizedBox(width: 8),
                _FilterChip('Visitor', _filter == 'Visitor', () => setState(() => _filter = 'Visitor')),
              ]),
              Text('${_snapshots} snapshots', style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textMuted)),
            ]),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(_snapshots, (i) => _SnapshotTile(index: i)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip(this.label, this.active, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: active ? MikeeColors.primary.withOpacity(0.15) : Colors.transparent, border: Border.all(color: active ? MikeeColors.primary : MikeeColors.border), borderRadius: BorderRadius.circular(20)), child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: active ? MikeeColors.primary : MikeeColors.textSecondary)))));
  }
}

class _SnapshotTile extends StatelessWidget {
  final int index;
  const _SnapshotTile({required this.index});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF141414), border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(16)),
      child: Stack(children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.blue.withOpacity(0.2), Colors.purple.withOpacity(0.1)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(child: Icon(Icons.image, size: 48, color: Colors.white.withOpacity(0.15))),
        ),
        Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(4)), child: Text('Manual', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500)))),
      ]),
    );
  }
}
