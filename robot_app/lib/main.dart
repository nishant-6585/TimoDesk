import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'battery_service.dart';
import 'config.dart';
import 'connecting_splash.dart';
import 'nav_points_provider.dart';
import 'services/kiosk.dart';

// #89 P1 — the robot chest screen now opens to an AMBIENT FACE (front-of-house
// shell), not the old _StreamScreen. The face → Dashboard → feature tiles. The
// background servers (MJPEG :8080, battery :8090, control :8081-3) are untouched
// and still start exactly as before. Providers/widgets/screens are split into:
//   providers.dart · app_widgets.dart · face_painter.dart · ambient_face_screen.dart
//   dashboard_screen.dart · status_screen.dart · control_screen.dart · settings_screen.dart

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Robot chest screen is LANDSCAPE-ONLY. Orientation is FIXED in the manifest
  // (android:screenOrientation="reverseLandscape") — a non-"USER" fixed value
  // that ignores the panel's rotation lock. Do NOT call
  // SystemChrome.setPreferredOrientations here: passing both landscape
  // directions yields SCREEN_ORIENTATION_USER_LANDSCAPE, which respects the
  // rotation lock and fell back to portrait on this panel.

  // Load persisted config (spine/camera URLs) before the UI reads it.
  await RobotConfig.load();

  // Kiosk: immersive (hide system bars) + enter Lock Task Mode. No-ops safely if
  // the app isn't device-owner. The Settings switch can re-allow Home/Recents/
  // status-bar for maintenance (kioskAllowSystemUi).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Enter Lock Task AFTER the first frame — startLockTask() requires a RESUMED
  // activity, so calling it here (before runApp) silently no-ops.
  WidgetsBinding.instance.addPostFrameCallback(
      (_) => Kiosk.start(allowSystemUi: RobotConfig.kioskAllowSystemUi));

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
      home: const ConnectingSplash(),
    );
  }
}
