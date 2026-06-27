import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/screens/login_screen.dart';
import 'adaptive_home.dart';
import '../features/control/screens/control_screen.dart';
import '../features/live_feed/screens/live_feed_screen.dart';
import '../features/gallery/screens/gallery_screen.dart';
import '../features/events/screens/event_log_screen.dart';
import '../features/patrol_routes/screens/patrol_routes_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/staff/screens/staff_enrollment_screen.dart';
import '../features/shared/layouts/app_shell.dart';

class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<AuthState> _subscription;

  GoRouterRefreshStream(Stream<AuthState> authStream) {
    _subscription = authStream.listen(
      (_) {
        notifyListeners();
      },
      onError: (_) {
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final _goRouterRefreshStreamProvider = Provider<GoRouterRefreshStream>((ref) {
  final refreshStream = GoRouterRefreshStream(
    Supabase.instance.client.auth.onAuthStateChange,
  );
  ref.onDispose(refreshStream.dispose);
  return refreshStream;
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final _isLoggedInProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.maybeWhen(
    data: (state) {
      final session = state.session;
      return session != null && session.accessToken.isNotEmpty;
    },
    orElse: () => false,
  );
});

final flavorProvider = StateProvider<String>((ref) {
  // MUST be explicitly set during app initialization in main.dart
  // before any router is built. This provider has no default value—
  // if not set, accessing it will throw to catch uninitialized flavor.
  throw StateError(
    'flavorProvider was not initialized. '
    'Call ref.read(flavorProvider.notifier).state = flavor in main.dart '
    'before building the router. Valid flavors: dev, staging, prod.',
  );
});

final routerProvider = Provider<GoRouter>((ref) {
  final refreshStream = ref.watch(_goRouterRefreshStreamProvider);
  final isLoggedIn = ref.watch(_isLoggedInProvider);
  final flavor = ref.watch(flavorProvider);

  // Validate flavor is one of the allowed values.
  assert(
    ['dev', 'staging', 'prod'].contains(flavor),
    'Invalid flavor: $flavor. Must be one of: dev, staging, prod',
  );

  return GoRouter(
    refreshListenable: refreshStream,
    redirect: (context, state) {
      // DEV ONLY: skip the login gate in 'dev' flavor only.
      // This auth bypass is ONLY enabled for true 'dev' flavor builds.
      // 'staging' and 'prod' flavors always enforce authentication.
      // NEVER bypass auth in staging or production builds.
      final devSkipAuth = flavor == 'dev';
      if (devSkipAuth) {
        return state.matchedLocation == '/login' ? '/' : null;
      }

      final isGoingToLogin = state.matchedLocation == '/login';

      if (!isLoggedIn && !isGoingToLogin) {
        return '/login';
      }

      if (isLoggedIn && isGoingToLogin) {
        return '/';
      }

      return null;
    },
    routes: [
      // Login lives outside the shell — no header/sidebar on the auth screen.
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      // Every navigable screen renders inside AppShell, so the top status bar
      // and left menu persist and only the body swaps on navigation.
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            name: 'dashboard',
            builder: (context, state) => const AdaptiveHome(),
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
              final captureId = state.pathParameters['captureId'] ?? '';
              if (captureId.isEmpty) {
                return const ErrorScreen(message: 'Invalid capture ID');
              }
              return GalleryScreen(captureId: captureId);
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
      ),
    ],
  );
});

class ErrorScreen extends StatelessWidget {
  final String message;

  const ErrorScreen({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
