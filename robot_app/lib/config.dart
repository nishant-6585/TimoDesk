import 'package:shared_preferences/shared_preferences.dart';

/// Editable, persisted robot config — surfaces the spine + camera base URLs that
/// used to be hardcoded consts in enroll_screen.dart so the Settings tile can
/// edit them. Loaded once at app start; readers use the static getters.
class RobotConfig {
  static const _kSpine = 'spine_base_url';
  static const _kCamera = 'camera_base_url';
  static const _kKiosk = 'kiosk_token';

  // Defaults = the values enroll_screen previously hardcoded. (DHCP — editable
  // in Settings; spine host changes between sessions.)
  static const String defaultSpine = 'http://192.168.1.18:4000';
  static const String defaultCamera = 'http://localhost:8080';

  static String spineBaseUrl = defaultSpine;
  static String cameraBaseUrl = defaultCamera;

  // Kiosk credential the chest screen sends to spine (WS auth + enrollment).
  // Empty by default → works only under spine's DEV_AUTH_BYPASS. In production,
  // set this to spine's KIOSK_TOKEN (same string) so the kiosk authenticates as
  // 'kiosk-robot'. See HANDOFF go-live item #5.
  static String kioskToken = '';

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    spineBaseUrl = p.getString(_kSpine) ?? defaultSpine;
    cameraBaseUrl = p.getString(_kCamera) ?? defaultCamera;
    kioskToken = p.getString(_kKiosk) ?? '';
  }

  static Future<void> setSpineBaseUrl(String v) async {
    spineBaseUrl = v.trim();
    (await SharedPreferences.getInstance()).setString(_kSpine, spineBaseUrl);
  }

  static Future<void> setCameraBaseUrl(String v) async {
    cameraBaseUrl = v.trim();
    (await SharedPreferences.getInstance()).setString(_kCamera, cameraBaseUrl);
  }

  static Future<void> setKioskToken(String v) async {
    kioskToken = v.trim();
    (await SharedPreferences.getInstance()).setString(_kKiosk, kioskToken);
  }

  /// The token to send to spine. Falls back to the dev bypass token when no
  /// kiosk credential is configured (works only behind DEV_AUTH_BYPASS).
  static String get authToken => kioskToken.isNotEmpty ? kioskToken : 'test-token';

  /// Spine base URL as a ws:// or wss:// origin (http→ws, https→wss).
  static String get spineWsUrl {
    var u = spineBaseUrl.trim();
    if (u.startsWith('https://')) return 'wss://${u.substring(8)}';
    if (u.startsWith('http://')) return 'ws://${u.substring(7)}';
    return u; // already ws:// or bare host
  }
}
