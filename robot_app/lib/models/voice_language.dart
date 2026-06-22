/// A voice language Mikee can speak. The ElevenLabs agent is configured with all
/// of these in the dashboard; we override `agent.language` per session with [code].
class VoiceLanguage {
  final String code; // ElevenLabs language code, e.g. "hi"
  final String name; // English display name, e.g. "Hindi"
  final String nativeName; // the language in its own script, e.g. "हिंदी"
  final String flag; // emoji flag

  const VoiceLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.flag,
  });
}

/// The 8 languages Mikee supports (matches the ElevenLabs agent config).
const List<VoiceLanguage> kSupportedLanguages = [
  VoiceLanguage(code: "en", name: "English", nativeName: "English", flag: "🇬🇧"),
  VoiceLanguage(code: "hi", name: "Hindi", nativeName: "हिंदी", flag: "🇮🇳"),
  VoiceLanguage(code: "ta", name: "Tamil", nativeName: "தமிழ்", flag: "🇮🇳"),
  VoiceLanguage(code: "ml", name: "Malayalam", nativeName: "മലയാളം", flag: "🇮🇳"),
  VoiceLanguage(code: "kn", name: "Kannada", nativeName: "ಕನ್ನಡ", flag: "🇮🇳"),
  VoiceLanguage(code: "te", name: "Telugu", nativeName: "తెలుగు", flag: "🇮🇳"),
  VoiceLanguage(code: "mr", name: "Marathi", nativeName: "मराठी", flag: "🇮🇳"),
  VoiceLanguage(code: "gu", name: "Gujarati", nativeName: "ગુજરાતી", flag: "🇮🇳"),
];

/// Look up a language by code; falls back to English.
VoiceLanguage languageForCode(String code) => kSupportedLanguages.firstWhere(
      (l) => l.code == code,
      orElse: () => kSupportedLanguages.first,
    );
