import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  String _filter = 'All';
  int _snapshots = 12;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: MikeeColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              // Header
              Container(
                height: 64,
                decoration: BoxDecoration(color: MikeeColors.surface.withOpacity(0.8), border: const Border(bottom: BorderSide(color: MikeeColors.border))),
                padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Row(children: [
                    Container(width: 36, height: 36, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [MikeeColors.primary, MikeeColors.primaryDark]), boxShadow: [BoxShadow(color: MikeeColors.primary.withOpacity(0.35), blurRadius: 16)]), child: Center(child: Text('X', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)))),
                    if (!compact) ...[const SizedBox(width: 12), Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Mikee', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary, height: 1.0)), Text('xboom', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.15, color: MikeeColors.textMuted, height: 1.0))])]
                  ]),
                  if (!compact) Text('Gallery', style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: MikeeColors.success.withOpacity(0.08), border: Border.all(color: MikeeColors.success.withOpacity(0.3)), borderRadius: BorderRadius.circular(8)), child: Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: MikeeColors.success)), const SizedBox(width: 8), Text('ONLINE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: MikeeColors.success))])),
                    const SizedBox(width: 12),
                    Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: MikeeColors.border, width: 2), color: const Color(0xFF2A2A2A)), child: Center(child: Text('NK', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)))),
                  ]),
                ]),
              ),
              Expanded(
                child: Row(
                  children: [
                    if (!compact) _Sidebar(onNav: (route) {
                      final routes = {'dashboard': '/', 'control': '/control', 'feed': '/live-feed', 'gallery': '/gallery', 'events': '/event-log', 'settings': '/settings'};
                      if (routes.containsKey(route)) context.go(routes[route]!);
                    }),
                    Expanded(
                      child: SingleChildScrollView(
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
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final Function(String) onNav;
  const _Sidebar({required this.onNav});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(color: MikeeColors.surface, border: const Border(right: BorderSide(color: MikeeColors.border))),
      child: Column(children: [Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [
        _NavItem('Dashboard', Icons.space_dashboard, false, () => onNav('dashboard')),
        _NavItem('Control', Icons.sports_esports, false, () => onNav('control')),
        _NavItem('Live Feed', Icons.videocam, false, () => onNav('feed')),
        _NavItem('Gallery', Icons.photo_library, true, () => onNav('gallery')),
        _NavItem('Event Log', Icons.receipt_long, false, () => onNav('events')),
        _NavItem('Settings', Icons.settings, false, () => onNav('settings')),
      ]))]),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _NavItem(this.label, this.icon, this.active, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: active ? MikeeColors.primary.withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [if (active) Container(width: 4, height: 20, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: MikeeColors.primary, borderRadius: BorderRadius.circular(999))), Icon(icon, size: 20, color: active ? MikeeColors.primary : MikeeColors.textSecondary), const SizedBox(width: 12), Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: active ? FontWeight.w500 : FontWeight.normal, color: active ? MikeeColors.primary : MikeeColors.textSecondary)))]),
    ))));
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
