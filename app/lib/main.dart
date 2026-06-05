import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/supabase.dart';
import 'core/theme.dart';
import 'core/router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await initSupabase();

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
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
