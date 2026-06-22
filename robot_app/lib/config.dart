import 'package:shared_preferences/shared_preferences.dart';

/// Editable, persisted robot config — surfaces the spine + camera base URLs that
/// used to be hardcoded consts in enroll_screen.dart so the Settings tile can
/// edit them. Loaded once at app start; readers use the static getters.
class RobotConfig {
  static const _kSpine = 'spine_base_url';
  static const _kCamera = 'camera_base_url';
  static const _kKiosk = 'kiosk_token';
  static const _kElevenKey = 'elevenlabs_api_key';
  static const _kElevenAgent = 'elevenlabs_agent_id';

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

  // ElevenLabs Conversational AI (#80 voice pipeline). Baked-in fleet defaults so a
  // fresh device works without per-device setup; a value saved in Settings still
  // overrides. The agent itself (LLM, voice, KB, prompt) is configured in the
  // ElevenLabs dashboard.
  static const String defaultElevenLabsAgentId = 'agent_0101kvhwdrnce6p8phkzj93e4kvb';

  // SECURITY NOTE: the API key is a secret. Baking it here commits it to git AND
  // ships it in the APK (extractable by anyone who has the build) — acceptable only
  // for a PRIVATE internal kiosk fleet. Restrict/rotate the key in the ElevenLabs
  // dashboard. To keep it OUT of git, blank the defaultValue below and pass the key
  // at build time: `flutter build apk --flavor robot --dart-define=ELEVENLABS_API_KEY=sk_...`.
  static const String defaultElevenLabsApiKey = String.fromEnvironment(
    'ELEVENLABS_API_KEY',
    defaultValue: 'sk_ad407f90175e1d153937e02d826a6cd2187ca02c329099f7',
  );

  static String elevenLabsApiKey = defaultElevenLabsApiKey;
  static String elevenLabsAgentId = defaultElevenLabsAgentId;

  // The agent's voice (from the ElevenLabs agent config) — used for dashboard
  // action-tile TTS so Mikee speaks in the SAME voice as the face screen.
  static const String defaultElevenLabsVoiceId = '6AUOG2nbfr0yFEeI0784';
  static String elevenLabsVoiceId = defaultElevenLabsVoiceId;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    spineBaseUrl = p.getString(_kSpine) ?? defaultSpine;
    cameraBaseUrl = p.getString(_kCamera) ?? defaultCamera;
    kioskToken = p.getString(_kKiosk) ?? '';
    elevenLabsApiKey = p.getString(_kElevenKey) ?? defaultElevenLabsApiKey;
    elevenLabsAgentId = p.getString(_kElevenAgent) ?? defaultElevenLabsAgentId;
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

  static Future<void> setElevenLabsApiKey(String v) async {
    elevenLabsApiKey = v.trim();
    (await SharedPreferences.getInstance()).setString(_kElevenKey, elevenLabsApiKey);
  }

  static Future<void> setElevenLabsAgentId(String v) async {
    elevenLabsAgentId = v.trim();
    (await SharedPreferences.getInstance()).setString(_kElevenAgent, elevenLabsAgentId);
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
