import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/control/screens/control_screen.dart';
import '../features/live_feed/screens/live_feed_screen.dart';
import '../features/gallery/screens/gallery_screen.dart';
import '../features/events/screens/event_log_screen.dart';
import '../features/patrol_routes/screens/patrol_routes_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/staff/screens/enroll_screen.dart';
import '../features/staff/screens/staff_enrollment_screen.dart';

// Fix 1: GoRouterRefreshStream listens to Supabase auth state changes
// This ensures the router re-evaluates the redirect condition when auth changes
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<AuthState> _subscription;

  GoRouterRefreshStream(Stream<AuthState> authStream) {
    _subscription = authStream.listen((_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    // Fix 1: refreshListenable re-evaluates redirect when auth state changes
    refreshListenable: GoRouterRefreshStream(
      Supabase.instance.client.auth.onAuthStateChange,
    ),
    redirect: (context, state) {
      final isLoggedIn = _isLoggedIn();
      final isGoingToLogin = state.matchedLocation == '/login';

      // Rule 1: If NOT logged in and NOT going to /login → redirect to /login
      if (!isLoggedIn && !isGoingToLogin) {
        return '/login';
      }

      // Rule 2: If logged in and trying to access /login → redirect to /
      if (isLoggedIn && isGoingToLogin) {
        return '/';
      }

      // Rule 3: All other cases → allow (logged in at allowed route, or at /login)
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        name: 'dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/control',
        name: 'control',
        builder: (context, state) => const ControlScreen(),
      ),
      GoRoute(
        path: '/live-feed',
        name: 'live_feed',
        builder: (context, state) => const LiveFeedScreen(),
      ),
      GoRoute(
        path: '/gallery',
        name: 'gallery',
        builder: (context, state) => const GalleryScreen(),
      ),
      GoRoute(
        path: '/gallery/:captureId',
        name: 'gallery_detail',
        builder: (context, state) {
          final captureId = state.pathParameters['captureId']!;
          return GalleryScreen();
        },
      ),
      GoRoute(
        path: '/event-log',
        name: 'events',
        builder: (context, state) => const EventLogScreen(),
      ),
      GoRoute(
        path: '/patrol-routes',
        name: 'patrol_routes',
        builder: (context, state) => const PatrolRoutesScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/enroll-staff',
        name: 'enroll_staff',
        builder: (context, state) => const StaffEnrollmentScreen(),
      ),
    ],
  );
});

bool _isLoggedIn() {
  // TODO: Re-enable authentication after testing
  return true; // Skip auth for now - go straight to dashboard
  // final session = Supabase.instance.client.auth.currentSession;
  // return session != null && session.accessToken.isNotEmpty;
}
