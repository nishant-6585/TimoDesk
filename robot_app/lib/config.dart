import 'package:shared_preferences/shared_preferences.dart';

/// Editable, persisted robot config — surfaces the spine + camera base URLs that
/// used to be hardcoded consts in enroll_screen.dart so the Settings tile can
/// edit them. Loaded once at app start; readers use the static getters.
class RobotConfig {
  static const _kSpine = 'spine_base_url';
  static const _kCamera = 'camera_base_url';

  // Defaults = the values enroll_screen previously hardcoded. (DHCP — editable
  // in Settings; spine host changes between sessions.)
  static const String defaultSpine = 'http://192.168.1.18:4000';
  static const String defaultCamera = 'http://localhost:8080';

  static String spineBaseUrl = defaultSpine;
  static String cameraBaseUrl = defaultCamera;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    spineBaseUrl = p.getString(_kSpine) ?? defaultSpine;
    cameraBaseUrl = p.getString(_kCamera) ?? defaultCamera;
  }

  static Future<void> setSpineBaseUrl(String v) async {
    spineBaseUrl = v.trim();
    (await SharedPreferences.getInstance()).setString(_kSpine, spineBaseUrl);
  }

  static Future<void> setCameraBaseUrl(String v) async {
    cameraBaseUrl = v.trim();
    (await SharedPreferences.getInstance()).setString(_kCamera, cameraBaseUrl);
  }
}
