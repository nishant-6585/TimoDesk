import 'package:flutter/material.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/control/screens/mobile_remote_screen.dart';

/// Breakpoint below which we treat the device as a phone and show the
/// phone-first remote (#90). Tablet/web keep the existing dashboard unchanged.
const double kPhoneBreakpoint = 600;

/// The app's home route. ONE codebase, adaptive by width — no separate app, no
/// duplicated providers. Phones → [MobileRemoteScreen]; tablet/web → the
/// existing [DashboardScreen] (and all other go_router routes are untouched).
class AdaptiveHome extends StatelessWidget {
  const AdaptiveHome({super.key});

  static const MobileRemoteScreen _mobileScreen = MobileRemoteScreen();
  static const DashboardScreen _dashboardScreen = DashboardScreen();

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < kPhoneBreakpoint;
    return RepaintBoundary(
      child: isMobile ? _mobileScreen : _dashboardScreen,
    );
  }
}
