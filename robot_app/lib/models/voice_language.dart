/// A voice language Mikee can speak. The ElevenLabs agent is configured with all
/// of these in the dashboard; we override `agent.language` per session with [code].
class VoiceLanguage {
  final String code; // ElevenLabs language code, e.g. "hi"
  final String name; // English display name, e.g. "Hindi"
  final String nativeName; // the language in its own script, e.g. "हिंदी"
  final String flag; // emoji flag

  // Greeting tokens (in this language) used by the approach/face greeting so the
  // spoken + on-screen hello matches the selected conversation language.
  final String hello; // greeting word, e.g. "नमस्ते"
  final String welcome; // "welcome to xboom" line, e.g. "xboom में आपका स्वागत है"

  const VoiceLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.flag,
    required this.hello,
    required this.welcome,
  });

  /// On-screen greeting pill text. [name] localises the named (spine) greet.
  String greetText([String? name]) =>
      name == null ? '$hello!' : '$hello, $name!';

  /// Spoken greeting phrase (fed to TTS). [name] localises the named greet.
  String greetSpeech([String? name]) =>
      name == null ? '$hello!' : '$hello $name! $welcome!';

  /// Render a configurable greeting template in this language.
  ///
  /// Placeholders: {hello} → the localised greeting word, {welcome} → the
  /// localised welcome line (with [company] substituted for the default brand),
  /// {name} → the recognised staff name, {company} → the company name itself.
  /// Templates are language-agnostic — the tokens carry the localisation.
  String renderGreeting(String template, {String? name, String? company}) {
    final c = (company == null || company.trim().isEmpty) ? 'xboom' : company.trim();
    final rendered = template
        .replaceAll('{hello}', hello)
        .replaceAll('{welcome}', welcome.replaceAll('xboom', c))
        .replaceAll('{company}', c)
        .replaceAll('{name}', name ?? '');
    // A staff template used without a name leaves a gap — collapse whitespace
    // and stray space-before-punctuation so the phrase still reads naturally.
    return rendered
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAllMapped(RegExp(r'\s+([!,.?])'), (m) => m[1]!)
        .trim();
  }
}

/// The 8 languages Mikee supports (matches the ElevenLabs agent config).
const List<VoiceLanguage> kSupportedLanguages = [
  VoiceLanguage(
      code: "en",
      name: "English",
      nativeName: "English",
      flag: "🇬🇧",
      hello: "Hello",
      welcome: "Welcome to xboom"),
  VoiceLanguage(
      code: "hi",
      name: "Hindi",
      nativeName: "हिंदी",
      flag: "🇮🇳",
      hello: "नमस्ते",
      welcome: "xboom में आपका स्वागत है"),
  VoiceLanguage(
      code: "ta",
      name: "Tamil",
      nativeName: "தமிழ்",
      flag: "🇮🇳",
      hello: "வணக்கம்",
      welcome: "xboom-க்கு வரவேற்கிறோம்"),
  VoiceLanguage(
      code: "ml",
      name: "Malayalam",
      nativeName: "മലയാളം",
      flag: "🇮🇳",
      hello: "നമസ്കാരം",
      welcome: "xboom-ലേക്ക് സ്വാഗതം"),
  VoiceLanguage(
      code: "kn",
      name: "Kannada",
      nativeName: "ಕನ್ನಡ",
      flag: "🇮🇳",
      hello: "ನಮಸ್ಕಾರ",
      welcome: "xboom ಗೆ ಸ್ವಾಗತ"),
  VoiceLanguage(
      code: "te",
      name: "Telugu",
      nativeName: "తెలుగు",
      flag: "🇮🇳",
      hello: "నమస్కారం",
      welcome: "xboom కి స్వాగతం"),
  VoiceLanguage(
      code: "mr",
      name: "Marathi",
      nativeName: "मराठी",
      flag: "🇮🇳",
      hello: "नमस्कार",
      welcome: "xboom मध्ये आपले स्वागत आहे"),
  VoiceLanguage(
      code: "gu",
      name: "Gujarati",
      nativeName: "ગુજરાતી",
      flag: "🇮🇳",
      hello: "નમસ્તે",
      welcome: "xboom માં આપનું સ્વાગત છે"),
];

/// Look up a language by code; falls back to English.
VoiceLanguage languageForCode(String code) => kSupportedLanguages.firstWhere(
      (l) => l.code == code,
      orElse: () => kSupportedLanguages.first,
    );
