import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/supabase.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'firebase_options.dart';
import 'services/push/push_service.dart';

/// Global messenger so push (#90) can show in-app banners over any screen.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Build flavor. Set at launch via `--dart-define=FLAVOR=dev|staging|prod`.
/// `flavorProvider` (router.dart) throws unless this is set before the router
/// is built, so it is injected via ProviderScope overrides in [main].
///
/// Defaults to `prod` — i.e. the login gate is ON unless you deliberately ask
/// for `dev`. It used to default to `dev`, which meant the documented ship
/// command (`flutter build web`, no --dart-define) produced a build with NO
/// login screen. Local development: `flutter run -d chrome --dart-define=FLAVOR=dev`.
const String _flavor = String.fromEnvironment('FLAVOR', defaultValue: 'prod');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await initSupabase();

  // Push notifications (#90 Part B). GUARDED: without Firebase config
  // (android/app/google-services.json + a Firebase project) this no-ops, so the
  // app still runs and Part A is unaffected. To activate: add the Firebase
  // config, apply the google-services Gradle plugin, then this wires itself up.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    PushService.messengerKey = rootMessengerKey;
    await PushService.init();
  } catch (e) {
    debugPrint('[main] Firebase/push not configured — notifications disabled: $e');
  }

  runApp(
    ProviderScope(
      overrides: [
        // Initialize the build flavor before the router is built.
        flavorProvider.overrideWith((ref) => _flavor),
      ],
      child: const MikeeApp(),
    ),
  );
}

class MikeeApp extends ConsumerWidget {
  const MikeeApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Mikee',
      theme: MikeeTheme.dark,
      scaffoldMessengerKey: rootMessengerKey,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
