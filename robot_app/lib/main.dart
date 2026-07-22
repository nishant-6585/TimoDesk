import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'battery_service.dart';
import 'config.dart';
import 'ambient_face_screen.dart';
import 'nav_points_provider.dart';

// #89 P1 — the robot chest screen now opens to an AMBIENT FACE (front-of-house
// shell), not the old _StreamScreen. The face → Dashboard → feature tiles. The
// background servers (MJPEG :8080, battery :8090, control :8081-3) are untouched
// and still start exactly as before. Providers/widgets/screens are split into:
//   providers.dart · app_widgets.dart · face_painter.dart · ambient_face_screen.dart
//   dashboard_screen.dart · status_screen.dart · control_screen.dart · settings_screen.dart

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted config (spine/camera URLs) before the UI reads it.
  await RobotConfig.load();

  // Start the battery HTTP server (:8090) that spine polls — unchanged.
  BatteryService().start();

  runApp(const ProviderScope(child: _App()));
}

const _orange = Color(0xFFFF6B35);

class _App extends ConsumerWidget {
  const _App();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Arm the navigation listener (arrival banner + spoken announcement) at
    // startup. Without this it only existed after the Navigation Points screen
    // was opened once — arrivals were silent if the app sat on the face screen.
    ref.read(navPointsProvider);
    return MaterialApp(
      title: 'Mikee — Robot',
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _orange, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        cardColor: const Color(0xFF1A1A1A),
      ),
      home: const AmbientFaceScreen(),
    );
  }
}
