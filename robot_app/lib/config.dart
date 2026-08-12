import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Editable, persisted robot config — surfaces the spine + camera base URLs that
/// used to be hardcoded consts in enroll_screen.dart so the Settings tile can
/// edit them. Loaded once at app start; readers use the static getters.
class RobotConfig {
  /// Bumped whenever an ElevenLabs credential changes (from the admin push OR
  /// the robot's own Settings) so the SpineClient can report the new state back
  /// to the admin — the robot→admin half of two-way key sync.
  static final ValueNotifier<int> elevenConfigRev = ValueNotifier<int>(0);

  /// Masked snapshot of the ElevenLabs credentials for admin sync. The API key
  /// is NEVER sent in full — only presence + last-4 — so the secret stays on the
  /// robot (mirrors the repo's MCP-token policy). Agent/voice ids sync in full.
  static Map<String, dynamic> elevenConfigReport() {
    final k = elevenLabsApiKey.trim();
    final ok = openaiApiKey.trim();
    return {
      'eleven_api_key_set': k.isNotEmpty,
      'eleven_api_key_hint': k.length > 4 ? k.substring(k.length - 4) : '',
      'eleven_agent_id': elevenLabsAgentId,
      'eleven_voice_id': elevenLabsVoiceId,
      'voice_preset': voicePresetName,
      // Voice-engine switch + OpenAI state (key masked, like the EL key).
      'voice_provider': voiceProvider,
      'openai_api_key_set': ok.isNotEmpty,
      'openai_api_key_hint': ok.length > 4 ? ok.substring(ok.length - 4) : '',
      'openai_voice': openaiVoice,
      'openai_model': openaiModel,
    };
  }

  static const _kSpine = 'spine_base_url';
  static const _kCamera = 'camera_base_url';
  static const _kKiosk = 'kiosk_token';
  static const _kElevenKey = 'elevenlabs_api_key';
  static const _kElevenAgent = 'elevenlabs_agent_id';
  static const _kVoiceLangCode = 'voice_language_code';
  static const _kVoiceLangName = 'voice_language_name';
  static const _kRobotName = 'robot_name';
  static const _kElevenVoiceId = 'elevenlabs_voice_id';
  static const _kVoicePresetName = 'voice_preset_name';
  static const _kVoiceProvider = 'voice_provider'; // 'elevenlabs' | 'openai'
  static const _kOpenaiKey = 'openai_api_key';
  static const _kOpenaiVoice = 'openai_voice';
  static const _kOpenaiModel = 'openai_model';
  static const _kCompanyName = 'company_name';
  static const _kGreetStaff = 'greet_staff_template';
  static const _kGreetVisitor = 'greet_visitor_template';
  static const _kRegreetMinutes = 'regreet_minutes';
  static const _kGateEnabled = 'attention_gate_enabled';
  static const _kGateMaxYaw = 'attention_max_yaw_deg';
  static const _kGateMinFace = 'attention_min_face_ratio';
  static const _kEscortReassureSecs = 'escort_reassure_seconds';
  static const _kEscortReassureText = 'escort_reassure_text';
  static const _kEscortLostText = 'escort_lost_text';

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

  // ── Kiosk + admin PIN ────────────────────────────────────────────────────
  // dashboardPin gates the admin area (Dashboard/Settings/Enroll) — a visitor
  // tapping the face screen must enter it. Change it in Settings. Default is a
  // simple factory PIN; set a real one on deployment.
  static const String _kDashboardPin = 'dashboard_pin';
  static String dashboardPin = '1234';
  // When true the kiosk lock-task allows Home / Recents / status-bar pulldown
  // (for admin/maintenance). Off = full lockdown. Toggle in Settings.
  static const String _kKioskAllowSystemUi = 'kiosk_allow_system_ui';
  static bool kioskAllowSystemUi = false;
  // When true the mic auto-opens after a greeting (person detected → listen).
  // Default OFF: the mic opens ONLY when a person taps the Talk button.
  static const String _kAutoOpenMic = 'auto_open_mic';
  static bool autoOpenMic = false;

  // ElevenLabs Conversational AI (#80 voice pipeline). Baked-in fleet defaults so a
  // fresh device works without per-device setup; a value saved in Settings still
  // overrides. The agent itself (LLM, voice, KB, prompt) is configured in the
  // ElevenLabs dashboard.
  static const String defaultElevenLabsAgentId = 'agent_0101kvhwdrnce6p8phkzj93e4kvb';

  // SECURITY: the API key is a secret and must NEVER be committed. Pass it at
  // build time (`flutter build apk --flavor robot --dart-define=ELEVENLABS_API_KEY=sk_...`)
  // or set it per device in Settings (persisted via SharedPreferences). The key
  // that used to live here as a defaultValue is in git history — rotate it in the
  // ElevenLabs dashboard.
  static const String defaultElevenLabsApiKey =
      String.fromEnvironment('ELEVENLABS_API_KEY');

  static String elevenLabsApiKey = defaultElevenLabsApiKey;
  static String elevenLabsAgentId = defaultElevenLabsAgentId;

  // The agent's voice (from the ElevenLabs agent config) — used for dashboard
  // action-tile TTS so the robot speaks in the SAME voice as the face screen.
  // Mutable at runtime: Settings voice presets and the "change your voice"
  // voice command both persist a new id here (TTS reads it per utterance; the
  // conversational agent picks it up on the next session via the tts override).
  static const String defaultElevenLabsVoiceId = '6AUOG2nbfr0yFEeI0784';
  static String elevenLabsVoiceId = defaultElevenLabsVoiceId;
  static String voicePresetName = 'Default';

  // ── Voice engine selection (switchable: ElevenLabs ↔ OpenAI Realtime) ──────
  // Which conversational-voice engine handles the live conversation + commands.
  // Switchable from the robot's own Settings OR the admin app (set_config →
  // applyRemoteConfig). Only one runs at a time. See services/voice_provider.dart.
  static const String voiceProviderElevenLabs = 'elevenlabs';
  static const String voiceProviderOpenAi = 'openai';
  static String voiceProvider = voiceProviderElevenLabs;

  // OpenAI Realtime credentials. Key is a secret (never committed) — set at build
  // time (--dart-define=OPENAI_API_KEY=sk-...) or per-device in Settings / admin.
  static const String defaultOpenaiApiKey = String.fromEnvironment('OPENAI_API_KEY');
  static String openaiApiKey = defaultOpenaiApiKey;
  // OpenAI Realtime voice (alloy / echo / shimmer / ash / ballad / coral / sage / verse).
  static String openaiVoice = 'alloy';
  // OpenAI Realtime model. GA name is 'gpt-realtime' (the old 'gpt-4o-realtime-
  // preview' is gone). Overridable via admin push so a future rename needs no
  // rebuild — the WS connects to wss://api.openai.com/v1/realtime?model=<this>.
  static String openaiModel = 'gpt-realtime';

  // ── Robot identity ─────────────────────────────────────────────────────────
  // The robot's NAME — editable in Settings and by voice ("change your name to
  // Rocky"). Used in UI titles, spoken confirmations, the {robot} greeting
  // placeholder, and passed to the ElevenLabs agent as the {{robot_name}}
  // dynamic variable (reference it in the dashboard system prompt).
  static const String defaultRobotName = 'Mini';
  static String robotName = defaultRobotName;

  // Voice language for the ElevenLabs Conversational AI session (the agent is
  // configured with 8 languages in the dashboard; we override per session). The
  // UI stays English — only Mini's spoken language changes. See voice_language.dart.
  static String voiceLanguageCode = 'en';
  static String voiceLanguageName = 'English';

  // ── Greetings (editable in Settings — the reception "voice" of the robot) ──
  // Templates use {hello} / {welcome} (localised via voice_language.dart) and
  // {name} (recognised staff). {welcome} substitutes {company} for the brand.
  static const String defaultCompanyName = 'xboom';
  static const String defaultGreetStaffTemplate = '{hello} {name}! {welcome}!';
  static const String defaultGreetVisitorTemplate = '{hello}! {welcome}!';

  static String companyName = defaultCompanyName;
  static String greetStaffTemplate = defaultGreetStaffTemplate;
  static String greetVisitorTemplate = defaultGreetVisitorTemplate;

  // Minutes before the same person is greeted by name again.
  static int regreetMinutes = 2;

  // ── Attention gate (greet only when a face is LOOKING at the camera) ──────
  // Gate on head pose + face size from the on-device ML Kit pass; when disabled
  // the old behaviour (greet on any fresh face presence) applies.
  static bool attentionGateEnabled = true;
  static double attentionMaxYawDeg = 18; // |head yaw| beyond this = looking away
  static double attentionMinFaceRatio = 0.12; // face-box height / frame height

  // ── Escort ("follow me" navigation) ────────────────────────────────────────
  // Mid-route reassurance cadence (0 = off) + phrase; and what to say after
  // arrival when nobody appears in front of the camera ({name} = the point).
  static int escortReassureSeconds = 12;
  static String escortReassureText = 'Stay with me.';
  static String escortLostText =
      'We got separated. I am at {name} if you need me.';

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    spineBaseUrl = p.getString(_kSpine) ?? defaultSpine;
    cameraBaseUrl = p.getString(_kCamera) ?? defaultCamera;
    kioskToken = p.getString(_kKiosk) ?? '';
    dashboardPin = p.getString(_kDashboardPin) ?? '1234';
    kioskAllowSystemUi = p.getBool(_kKioskAllowSystemUi) ?? false;
    autoOpenMic = p.getBool(_kAutoOpenMic) ?? false;
    elevenLabsApiKey = p.getString(_kElevenKey) ?? defaultElevenLabsApiKey;
    elevenLabsAgentId = p.getString(_kElevenAgent) ?? defaultElevenLabsAgentId;
    voiceLanguageCode = p.getString(_kVoiceLangCode) ?? 'en';
    voiceLanguageName = p.getString(_kVoiceLangName) ?? 'English';
    companyName = p.getString(_kCompanyName) ?? defaultCompanyName;
    greetStaffTemplate = p.getString(_kGreetStaff) ?? defaultGreetStaffTemplate;
    greetVisitorTemplate =
        p.getString(_kGreetVisitor) ?? defaultGreetVisitorTemplate;
    regreetMinutes = p.getInt(_kRegreetMinutes) ?? 2;
    attentionGateEnabled = p.getBool(_kGateEnabled) ?? true;
    attentionMaxYawDeg = p.getDouble(_kGateMaxYaw) ?? 18;
    attentionMinFaceRatio = p.getDouble(_kGateMinFace) ?? 0.12;
    escortReassureSeconds = p.getInt(_kEscortReassureSecs) ?? 12;
    escortReassureText =
        p.getString(_kEscortReassureText) ?? escortReassureText;
    escortLostText = p.getString(_kEscortLostText) ?? escortLostText;
    robotName = p.getString(_kRobotName) ?? defaultRobotName;
    elevenLabsVoiceId = p.getString(_kElevenVoiceId) ?? defaultElevenLabsVoiceId;
    voicePresetName = p.getString(_kVoicePresetName) ?? 'Default';
    voiceProvider = p.getString(_kVoiceProvider) ?? voiceProviderElevenLabs;
    openaiApiKey = p.getString(_kOpenaiKey) ?? defaultOpenaiApiKey;
    openaiVoice = p.getString(_kOpenaiVoice) ?? 'alloy';
    openaiModel = p.getString(_kOpenaiModel) ?? 'gpt-realtime';
  }

  /// Rename the robot (Settings field or the "change your name to X" voice
  /// command). Empty → back to the default.
  static Future<void> setRobotName(String v) async {
    final name = v.trim();
    robotName = name.isEmpty ? defaultRobotName : name;
    (await SharedPreferences.getInstance()).setString(_kRobotName, robotName);
  }

  /// Apply a config map pushed from the web admin (spine config_update). Only
  /// known keys are honoured; each persists so it survives an app restart.
  static Future<void> applyRemoteConfig(Map<String, dynamic> cfg) async {
    if (cfg['robot_name'] is String) {
      await setRobotName(cfg['robot_name'] as String);
    }
    if (cfg['company_name'] is String) {
      companyName = (cfg['company_name'] as String).trim().isEmpty
          ? defaultCompanyName
          : (cfg['company_name'] as String).trim();
      (await SharedPreferences.getInstance())
          .setString(_kCompanyName, companyName);
    }
    if (cfg['greet_visitor'] is String &&
        (cfg['greet_visitor'] as String).trim().isNotEmpty) {
      greetVisitorTemplate = (cfg['greet_visitor'] as String).trim();
      (await SharedPreferences.getInstance())
          .setString(_kGreetVisitor, greetVisitorTemplate);
    }
    if (cfg['escort_reassure_seconds'] is num) {
      escortReassureSeconds =
          (cfg['escort_reassure_seconds'] as num).toInt().clamp(0, 120);
      (await SharedPreferences.getInstance())
          .setInt(_kEscortReassureSecs, escortReassureSeconds);
    }
    if (cfg['attention_gate'] is bool) {
      attentionGateEnabled = cfg['attention_gate'] as bool;
      (await SharedPreferences.getInstance())
          .setBool(_kGateEnabled, attentionGateEnabled);
    }
    // ElevenLabs credentials pushed from the admin app. Write-only: a blank
    // field is ignored so pushing other settings never wipes a saved key.
    if (cfg['elevenlabs_api_key'] is String &&
        (cfg['elevenlabs_api_key'] as String).trim().isNotEmpty) {
      await setElevenLabsApiKey(cfg['elevenlabs_api_key'] as String);
    }
    if (cfg['elevenlabs_agent_id'] is String &&
        (cfg['elevenlabs_agent_id'] as String).trim().isNotEmpty) {
      await setElevenLabsAgentId(cfg['elevenlabs_agent_id'] as String);
    }
    if (cfg['elevenlabs_voice_id'] is String &&
        (cfg['elevenlabs_voice_id'] as String).trim().isNotEmpty) {
      await setVoice(cfg['elevenlabs_voice_id'] as String, voicePresetName);
    }
    // Voice-engine switch + OpenAI creds pushed from the admin. voice_provider is
    // applied even if blankable-guarded elsewhere; the key is write-only (blank
    // never overwrites a saved key).
    if (cfg['voice_provider'] is String &&
        (cfg['voice_provider'] as String).trim().isNotEmpty) {
      await setVoiceProvider(cfg['voice_provider'] as String);
    }
    if (cfg['openai_api_key'] is String &&
        (cfg['openai_api_key'] as String).trim().isNotEmpty) {
      await setOpenaiApiKey(cfg['openai_api_key'] as String);
    }
    if (cfg['openai_voice'] is String &&
        (cfg['openai_voice'] as String).trim().isNotEmpty) {
      await setOpenaiVoice(cfg['openai_voice'] as String);
    }
    if (cfg['openai_model'] is String &&
        (cfg['openai_model'] as String).trim().isNotEmpty) {
      await setOpenaiModel(cfg['openai_model'] as String);
    }
  }

  /// Switch the speaking voice (Settings preset or the "change your voice"
  /// voice command). TTS uses it immediately; the conversational agent picks
  /// it up when the next session opens.
  static Future<void> setVoice(String voiceId, String presetName) async {
    elevenLabsVoiceId = voiceId.trim().isEmpty ? defaultElevenLabsVoiceId : voiceId.trim();
    voicePresetName = presetName;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kElevenVoiceId, elevenLabsVoiceId);
    await p.setString(_kVoicePresetName, voicePresetName);
    elevenConfigRev.value++;
  }

  /// Persist the escort settings (Settings screen SAVE).
  static Future<void> updateEscortConfig({
    required int reassureSeconds,
    required String reassureText,
    required String lostText,
  }) async {
    escortReassureSeconds = reassureSeconds.clamp(0, 120);
    escortReassureText = reassureText.trim();
    escortLostText = lostText.trim();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kEscortReassureSecs, escortReassureSeconds);
    await p.setString(_kEscortReassureText, escortReassureText);
    await p.setString(_kEscortLostText, escortLostText);
  }

  /// Persist the greeting + attention-gate settings (Settings screen SAVE).
  static Future<void> updateGreetingConfig({
    required String company,
    required String staffTemplate,
    required String visitorTemplate,
    required int regreetMins,
    required bool gateEnabled,
    required double gateMaxYawDeg,
    required double gateMinFaceRatio,
  }) async {
    companyName = company.trim().isEmpty ? defaultCompanyName : company.trim();
    greetStaffTemplate = staffTemplate.trim().isEmpty
        ? defaultGreetStaffTemplate
        : staffTemplate.trim();
    greetVisitorTemplate = visitorTemplate.trim().isEmpty
        ? defaultGreetVisitorTemplate
        : visitorTemplate.trim();
    regreetMinutes = regreetMins.clamp(1, 24 * 60);
    attentionGateEnabled = gateEnabled;
    attentionMaxYawDeg = gateMaxYawDeg.clamp(5, 60);
    attentionMinFaceRatio = gateMinFaceRatio.clamp(0.02, 0.6);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCompanyName, companyName);
    await p.setString(_kGreetStaff, greetStaffTemplate);
    await p.setString(_kGreetVisitor, greetVisitorTemplate);
    await p.setInt(_kRegreetMinutes, regreetMinutes);
    await p.setBool(_kGateEnabled, attentionGateEnabled);
    await p.setDouble(_kGateMaxYaw, attentionMaxYawDeg);
    await p.setDouble(_kGateMinFace, attentionMinFaceRatio);
  }

  /// Persist the selected voice language (code + display name).
  static Future<void> updateVoiceLanguage(String code, String name) async {
    voiceLanguageCode = code;
    voiceLanguageName = name;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kVoiceLangCode, code);
    await p.setString(_kVoiceLangName, name);
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

  static Future<void> setDashboardPin(String v) async {
    dashboardPin = v.trim().isEmpty ? '1234' : v.trim();
    (await SharedPreferences.getInstance()).setString(_kDashboardPin, dashboardPin);
  }

  static Future<void> setKioskAllowSystemUi(bool v) async {
    kioskAllowSystemUi = v;
    (await SharedPreferences.getInstance()).setBool(_kKioskAllowSystemUi, v);
  }

  static Future<void> setAutoOpenMic(bool v) async {
    autoOpenMic = v;
    (await SharedPreferences.getInstance()).setBool(_kAutoOpenMic, v);
  }

  static Future<void> setElevenLabsApiKey(String v) async {
    elevenLabsApiKey = v.trim();
    (await SharedPreferences.getInstance()).setString(_kElevenKey, elevenLabsApiKey);
    elevenConfigRev.value++; // → SpineClient reports masked state to admin
  }

  /// Switch the live voice engine ('elevenlabs' | 'openai'). Unknown values fall
  /// back to ElevenLabs. Persisted + reported to the admin (two-way sync).
  static Future<void> setVoiceProvider(String v) async {
    final p = v.trim().toLowerCase();
    voiceProvider = p == voiceProviderOpenAi ? voiceProviderOpenAi : voiceProviderElevenLabs;
    (await SharedPreferences.getInstance()).setString(_kVoiceProvider, voiceProvider);
    elevenConfigRev.value++;
  }

  static Future<void> setOpenaiApiKey(String v) async {
    openaiApiKey = v.trim();
    (await SharedPreferences.getInstance()).setString(_kOpenaiKey, openaiApiKey);
    elevenConfigRev.value++;
  }

  static Future<void> setOpenaiVoice(String v) async {
    openaiVoice = v.trim().isEmpty ? 'alloy' : v.trim();
    (await SharedPreferences.getInstance()).setString(_kOpenaiVoice, openaiVoice);
    elevenConfigRev.value++;
  }

  static Future<void> setOpenaiModel(String v) async {
    openaiModel = v.trim().isEmpty ? 'gpt-realtime' : v.trim();
    (await SharedPreferences.getInstance()).setString(_kOpenaiModel, openaiModel);
    elevenConfigRev.value++;
  }

  static Future<void> setElevenLabsAgentId(String v) async {
    elevenLabsAgentId = v.trim();
    (await SharedPreferences.getInstance()).setString(_kElevenAgent, elevenLabsAgentId);
    elevenConfigRev.value++;
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
