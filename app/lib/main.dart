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
    const ProviderScope(
      child: TimoDeskApp(),
    ),
  );
}

class TimoDeskApp extends ConsumerWidget {
  const TimoDeskApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'TimoDesk',
      theme: TimoTheme.dark,
      scaffoldMessengerKey: rootMessengerKey,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
