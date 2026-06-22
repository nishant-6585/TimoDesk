import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import 'package:google_fonts/google_fonts.dart';

class MainLayout extends StatelessWidget {
  final Widget child;
  final String activeNav;

  const MainLayout({Key? key, required this.child, required this.activeNav}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 900;
    return Scaffold(
      backgroundColor: MikeeColors.background,
      body: Column(children: [
        Expanded(
          child: Row(children: [
            if (!compact) _Sidebar(active: activeNav, onNav: (route) {
              final routes = {'dashboard': '/', 'control': '/control', 'feed': '/live-feed', 'gallery': '/gallery', 'events': '/event-log', 'settings': '/settings'};
              if (routes.containsKey(route)) context.go(routes[route]!);
            }),
            Expanded(child: child),
          ]),
        ),
      ]),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final String active;
  final Function(String) onNav;
  const _Sidebar({required this.active, required this.onNav});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(color: MikeeColors.surface, border: const Border(right: BorderSide(color: MikeeColors.border))),
      child: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [
          _NavItem('Dashboard', Icons.space_dashboard, active == 'dashboard', () => onNav('dashboard')),
          _NavItem('Control', Icons.sports_esports, active == 'control', () => onNav('control')),
          _NavItem('Live Feed', Icons.videocam, active == 'feed', () => onNav('feed')),
          _NavItem('Gallery', Icons.photo_library, active == 'gallery', () => onNav('gallery')),
          _NavItem('Event Log', Icons.receipt_long, active == 'events', () => onNav('events')),
          _NavItem('Settings', Icons.settings, active == 'settings', () => onNav('settings')),
        ])),
      ]),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: active ? MikeeColors.primary.withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          if (active) Container(width: 4, height: 20, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: MikeeColors.primary, borderRadius: BorderRadius.circular(999))),
          Icon(icon, size: 20, color: active ? MikeeColors.primary : MikeeColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: active ? FontWeight.w500 : FontWeight.normal, color: active ? MikeeColors.primary : MikeeColors.textSecondary))),
        ]),
      ))),
    );
  }
}
