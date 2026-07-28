/// persona_voice.dart — voice commands that change the robot's IDENTITY:
///
///   "change your name to Rocky" / "your name is now Rocky" /
///   "change your name from Minee to Rocky"      → rename
///   "change your voice to rocky" / "sound deeper" / "use a female voice"
///                                               → switch ElevenLabs voice preset
///
/// Pure matching (no side effects) so it's unit-testable; the caller applies
/// the change via RobotConfig and speaks the confirmation.
library;

import 'voice_fuzzy.dart';

/// A selectable ElevenLabs voice. The ids are ElevenLabs premade voices
/// (available on every account) plus the fleet default; [keywords] are what a
/// visitor might SAY to ask for it ("sound like rocky", "a deeper voice").
class VoicePreset {
  const VoicePreset(this.name, this.voiceId, this.keywords);

  final String name;
  final String voiceId;
  final List<String> keywords;
}

const List<VoicePreset> kVoicePresets = [
  // Fleet default (the agent's dashboard voice).
  VoicePreset('Default', '6AUOG2nbfr0yFEeI0784', ['default', 'normal', 'original']),
  // ElevenLabs premade voices.
  VoicePreset('Rocky (deep)', 'pNInz6obpgDQGcFmaJgB', // Adam
      ['rocky', 'deep', 'deeper', 'strong', 'tough', 'man', 'male']),
  VoicePreset('Josh (young)', 'TxGEqnHWrfWFTfGW9XjX',
      ['josh', 'young', 'younger', 'casual', 'boy']),
  VoicePreset('Rachel (calm)', '21m00Tcm4TlvDq8ikWAM',
      ['rachel', 'calm', 'female', 'woman', 'lady', 'girl']),
  VoicePreset('Bella (soft)', 'EXAVITQu4vr4xnSDxMaL',
      ['bella', 'soft', 'gentle', 'sweet']),
];

enum PersonaCommandKind { rename, voice }

class PersonaVoiceResult {
  const PersonaVoiceResult._(this.isCommand, this.kind, this.newName, this.preset, this.heard);

  static const PersonaVoiceResult notACommand =
      PersonaVoiceResult._(false, null, null, null, '');

  const PersonaVoiceResult.rename(String this.newName)
      : isCommand = true,
        kind = PersonaCommandKind.rename,
        preset = null,
        heard = '';

  const PersonaVoiceResult.voice(VoicePreset this.preset, this.heard)
      : isCommand = true,
        kind = PersonaCommandKind.voice,
        newName = null;

  /// A voice command whose requested voice matched NO preset — the caller
  /// should list what's available. [heard] is what the visitor asked for.
  const PersonaVoiceResult.voiceUnknown(this.heard)
      : isCommand = true,
        kind = PersonaCommandKind.voice,
        newName = null,
        preset = null;

  final bool isCommand;
  final PersonaCommandKind? kind;
  final String? newName;
  final VoicePreset? preset;
  final String heard;
}

class PersonaVoice {
  // "change/set your name to X", "your name is (now) X", "call yourself X",
  // "rename yourself (to) X", "we will call you X", "i will call you X".
  // The optional "from <old> to" middle handles "change your name from A to B".
  static final RegExp _rename = RegExp(
    r'\b(?:(?:change|set)\s+(?:your|the)\s+name(?:\s+from\s+.+?)?\s+to|'
    r'your\s+name\s+is(?:\s+now)?|'
    r'call\s+your\s*self|'
    r'rename\s+your\s*self(?:\s+to)?|'
    r'(?:we|i)(?:\s+wi?ll)?\s+call\s+you)\s+(.+)$',
    caseSensitive: false,
  );

  // "change your voice to X", "speak like X", "sound like X", "use a X voice",
  // "make your voice X", "talk in a X voice", "sound X" ("sound deeper").
  static final RegExp _voice = RegExp(
    r'\b(?:(?:change|set|make)\s+(?:your|the)\s+voice(?:\s+to(?:\s+(?:feel|sound)\s+like)?)?|'
    r'(?:speak|sound|talk)\s+like(?:\s+a)?|'
    r'use\s+a[n]?|'
    r'sound)\s+(.+?)(?:\s+voice)?$',
    caseSensitive: false,
  );

  /// Try to parse [transcript] as a persona command. Rename wins over voice
  /// when both patterns fire ("change your name…" contains no voice keyword,
  /// but be deterministic anyway).
  static PersonaVoiceResult match(String transcript) {
    final t = transcript.trim();
    final rn = _rename.firstMatch(t);
    if (rn != null) {
      var name = fuzzyNormalize(rn.group(1)!);
      // "…to rocky and change your voice…" → keep only the name itself.
      name = name.split(RegExp(r'\band\b')).first.trim();
      // Take at most two words; title-case for display/speech.
      final words = name.split(' ').where((w) => w.isNotEmpty).take(2).map(
          (w) => w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''));
      final clean = words.join(' ');
      if (clean.isEmpty || clean.length > 24) return PersonaVoiceResult.notACommand;
      return PersonaVoiceResult.rename(clean);
    }

    // Voice command needs the word "voice"/"speak"/"sound"/"talk" somewhere —
    // _voice's alternation guarantees that by construction.
    final vc = _voice.firstMatch(t);
    if (vc != null && RegExp(r'\b(voice|speak|sound|talk)\b', caseSensitive: false).hasMatch(t)) {
      final heard = fuzzyNormalize(vc.group(1)!);
      if (heard.isEmpty) return PersonaVoiceResult.notACommand;
      VoicePreset? best;
      double bestScore = 0;
      for (final p in kVoicePresets) {
        for (final kw in p.keywords) {
          final s = fuzzyScore(heard, kw);
          if (s > bestScore) {
            bestScore = s;
            best = p;
          }
        }
      }
      if (best != null && bestScore >= 0.5) {
        return PersonaVoiceResult.voice(best, heard);
      }
      return PersonaVoiceResult.voiceUnknown(heard);
    }

    return PersonaVoiceResult.notACommand;
  }
}
