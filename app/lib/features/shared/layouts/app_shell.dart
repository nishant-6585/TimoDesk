import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../services/spine/spine_provider.dart';

/// Persistent application shell: a top status bar and a left navigation rail
/// that stay mounted across route changes. Only [child] (the routed body)
/// swaps when the user navigates, so the menu and status bar never rebuild
/// from scratch or flash a new page.
class AppShell extends ConsumerWidget {
  final Widget child;

  const AppShell({Key? key, required this.child}) : super(key: key);

  static const Map<String, String> _navRoutes = {
    'dashboard': '/',
    'control': '/control',
    // "Enrol Staff" reuses the live-feed screen, which hosts the web webcam
    // enrollment flow (face-api.js) behind its "Enroll Staff" toggle.
    'enroll': '/live-feed',
    'gallery': '/gallery',
    'events': '/event-log',
    'navigation': '/navigation',
    'patrol_routes': '/patrol-routes',
    'settings': '/settings',
  };

  String _activeFor(String location) {
    if (location == '/') return 'dashboard';
    if (location.startsWith('/control')) return 'control';
    if (location.startsWith('/live-feed') || location.startsWith('/enroll-staff')) return 'enroll';
    if (location.startsWith('/gallery')) return 'gallery';
    if (location.startsWith('/event-log')) return 'events';
    if (location.startsWith('/navigation')) return 'navigation';
    if (location.startsWith('/patrol-routes')) return 'patrol_routes';
    if (location.startsWith('/settings')) return 'settings';
    return 'dashboard';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spine = ref.watch(spineProvider);
    // Robot reachability, not just the browser↔spine link (matches Navigation).
    final online = spine.connected && (spine.status?.online ?? false);
    final rawBattery = spine.status?.battery;
    final int? battery = (rawBattery != null && rawBattery >= 0) ? rawBattery : null;
    final bool charging = spine.status?.isCharging ?? false;

    final location = GoRouterState.of(context).uri.path;
    final active = _activeFor(location);
    final compact = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: MikeeColors.background,
      body: Column(
        children: [
          _ShellHeader(compact: compact, online: online, battery: battery, charging: charging),
          Expanded(
            child: Row(
              children: [
                if (!compact)
                  _ShellSidebar(
                    active: active,
                    onNav: (key) {
                      final dest = _navRoutes[key];
                      if (dest != null && dest != location) context.go(dest);
                    },
                  ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellHeader extends StatelessWidget {
  final bool compact;
  final bool online;
  final int? battery; // null = unknown → shown as "—"
  final bool charging; // robot on charger → show bolt + amber

  const _ShellHeader({required this.compact, required this.online, required this.battery, this.charging = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: MikeeColors.surface.withOpacity(0.8),
        border: const Border(bottom: BorderSide(color: MikeeColors.border)),
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Logo lockup
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [MikeeColors.primary, MikeeColors.primaryDark],
                ),
                boxShadow: [BoxShadow(color: MikeeColors.primary.withOpacity(0.35), blurRadius: 16)],
              ),
              child: Center(child: Text('X', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))),
            ),
            if (!compact) ...[
              const SizedBox(width: 12),
              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mikee', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary, height: 1.0)),
                Text('xboom', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.15, color: MikeeColors.textMuted, height: 1.0)),
              ]),
            ]
          ]),
          // Center: Subtitle (desktop only)
          if (!compact)
            Text(
              'Mikee — Reception Robot',
              style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary),
            ),
          // Right: Status pills and avatar
          Row(children: [
            if (!compact) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: MikeeColors.cardTop, border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(8)),
                child: Builder(builder: (_) {
                  // Charging → amber + bolt; low (<20%) → red; else green.
                  final Color barColor = battery == null
                      ? MikeeColors.textMuted
                      : charging
                          ? const Color(0xFFFFA726) // amber while charging
                          : (battery! < 20 ? MikeeColors.error : MikeeColors.success);
                  final IconData icon = battery == null
                      ? Icons.battery_unknown
                      : charging
                          ? Icons.bolt
                          : (battery! < 20 ? Icons.battery_alert : Icons.battery_full);
                  return Row(children: [
                    Icon(icon, size: 16, color: barColor),
                    const SizedBox(width: 8),
                    Text(battery == null ? '—' : '$battery%${charging ? ' ⚡' : ''}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w500, color: barColor)),
                    const SizedBox(width: 8),
                    Container(
                      width: 40,
                      height: 6,
                      decoration: BoxDecoration(color: MikeeColors.border, borderRadius: BorderRadius.circular(999)),
                      child: Stack(children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: (40 * (battery ?? 0) / 100).clamp(0, 40),
                            height: 6,
                            decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(999)),
                          ),
                        )
                      ]),
                    ),
                  ]);
                }),
              ),
              const SizedBox(width: 12),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (online ? MikeeColors.success : MikeeColors.error).withOpacity(0.08),
                border: Border.all(color: (online ? MikeeColors.success : MikeeColors.error).withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: online ? MikeeColors.success : MikeeColors.error)),
                const SizedBox(width: 8),
                Text(online ? 'ONLINE' : 'OFFLINE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.05, color: online ? MikeeColors.success : MikeeColors.error)),
              ]),
            ),
            const SizedBox(width: 12),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: MikeeColors.border, width: 2), color: const Color(0xFF2A2A2A)),
              child: Center(child: Text('NK', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white))),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ShellSidebar extends StatelessWidget {
  final String active;
  final Function(String) onNav;

  const _ShellSidebar({required this.active, required this.onNav});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: MikeeColors.surface,
        border: const Border(right: BorderSide(color: MikeeColors.border)),
      ),
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _NavItem('Dashboard', Icons.space_dashboard, active == 'dashboard', () => onNav('dashboard')),
              _NavItem('Control', Icons.sports_esports, active == 'control', () => onNav('control')),
              _NavItem('Enrol Staff', Icons.person_add, active == 'enroll', () => onNav('enroll')),
              _NavItem('Gallery', Icons.photo_library, active == 'gallery', () => onNav('gallery')),
              _NavItem('Event Log', Icons.receipt_long, active == 'events', () => onNav('events')),
              _NavItem('Navigation', Icons.pin_drop, active == 'navigation', () => onNav('navigation')),
              _NavItem('Patrol Routes', Icons.route, active == 'patrol_routes', () => onNav('patrol_routes')),
              _NavItem('Settings', Icons.settings, active == 'settings', () => onNav('settings')),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: MikeeColors.border))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('v0.1.0', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: MikeeColors.textMuted)),
            const SizedBox(height: 4),
            Text('xboom · Land Air Water', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF4A4A4A))),
          ]),
        ),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: active ? MikeeColors.primary.withOpacity(0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              if (active) Container(width: 4, height: 20, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: MikeeColors.primary, borderRadius: BorderRadius.circular(999))),
              Icon(icon, size: 20, color: active ? MikeeColors.primary : MikeeColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: active ? MikeeColors.primary : MikeeColors.textSecondary)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
