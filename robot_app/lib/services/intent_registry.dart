/// intent_registry.dart — Step 1 of the configurable voice-command architecture.
///
/// Consolidates the previously scattered on-device matchers (stop, navigation,
/// dock, persona, check-in) behind ONE priority-ordered registry. The UI used to
/// chain `if (_handleStop(t)) return; if (_handleNav(t)) return; …`, duplicating
/// the order and the "who wins" rules across call sites. Here the order lives in
/// exactly one place — [_intents] — and callers dispatch a single [match].
///
/// This is deliberately behavior-preserving: each [VoiceIntent] delegates to the
/// SAME matcher that already shipped, in the SAME order (stop always wins, then
/// navigation/dock, persona, check-in). It adds the seam the roadmap needs — a
/// declarative catalog, later fed from the spine — without changing what matches
/// today. Wiring the ambient-face / agent-transcript call sites onto this is the
/// next step (kept separate so it can be verified on hardware on its own).
library;

import 'nav_points_api.dart';
import 'nav_voice.dart';
import 'persona_voice.dart';
import 'checkin_voice.dart';

/// The kind of on-device command a transcript resolved to. Grouped by skill:
///  • system    — stop, resume, volume, language, sleepWake, help
///  • navigation — navigate, dock, cancelNav, patrol, escort
///  • social     — gesture (wave / reset), snapshot, drive
///  • reception  — checkin
///  • persona    — persona (rename / voice)
/// Each maps to a real capability: navigation/patrol/escort/dock/cancelNav and
/// drive/gesture/snapshot are spine intents; volume/language/sleepWake/help are
/// app-level. Adding a kind here + a matcher below is how a use case is added
/// today; the roadmap moves the phrase lists into the spine catalog.
enum VoiceIntentKind {
  stop,
  resume,
  navigate,
  dock,
  cancelNav,
  patrol,
  escort,
  gesture,
  snapshot,
  drive,
  volume,
  language,
  sleepWake,
  help,
  persona,
  checkin,
}

/// A resolved command: its [kind] plus any extracted slots. Slots are kept as a
/// small typed map so new intents can carry their own payload without widening
/// this class each time (`point`, `personName`, `personaKind`, `voicePreset`,
/// `host`, `heard`).
class IntentMatch {
  const IntentMatch(this.kind, {this.slots = const {}});
  final VoiceIntentKind kind;
  final Map<String, Object?> slots;

  T? slot<T>(String key) => slots[key] as T?;

  @override
  String toString() => 'IntentMatch($kind, $slots)';
}

/// Everything a matcher may need beyond the raw transcript. Passed in (not read
/// from providers) so the registry stays pure and unit-testable.
class IntentContext {
  const IntentContext({this.navPoints = const []});
  final List<NavPoint> navPoints;
}

/// One recognizable command. Returns an [IntentMatch] when the transcript is its
/// command, or null to let the next intent (or the conversational agent) handle
/// it. Lower [priority] is checked first.
abstract class VoiceIntent {
  String get id;
  int get priority;
  IntentMatch? match(String transcript, IntentContext ctx);
}

/// Priority-ordered dispatch. The first intent to claim the transcript wins —
/// mirroring the old if-chain order exactly.
class IntentRegistry {
  IntentRegistry(List<VoiceIntent> intents,
      {Set<VoiceIntentKind> disabledKinds = const {}})
      : _intents = List.unmodifiable(
          [...intents]..sort((a, b) => a.priority.compareTo(b.priority)),
        ),
        _disabled = disabledKinds;

  final List<VoiceIntent> _intents;
  // Kinds the deployment has switched OFF in the spine catalog. A match whose
  // kind is disabled is treated as "not a command" — the robot stops acting on
  // it (and the conversational agent may still answer).
  final Set<VoiceIntentKind> _disabled;

  /// The intents in dispatch order — exposed for tests / an admin view.
  List<VoiceIntent> get intents => _intents;

  /// Kinds currently switched off (from the catalog).
  Set<VoiceIntentKind> get disabledKinds => _disabled;

  /// Resolve [transcript] to a command, or null for "let the agent answer".
  IntentMatch? match(String transcript, [IntentContext ctx = const IntentContext()]) {
    for (final intent in _intents) {
      final m = intent.match(transcript, ctx);
      if (m != null && !_disabled.contains(m.kind)) return m;
    }
    return null;
  }

  /// Build the registry from the spine's voice command catalog: the same code
  /// matchers (which own the slot logic), but with any command the deployment
  /// disabled switched off. Unknown/absent catalog rows keep their code default
  /// enabled, so a newly-added code intent is never silently dropped. Phrase
  /// editing for the fuzzy/slot intents stays in code for now; the catalog owns
  /// enable/disable today (and feeds the LLM tier its examples).
  static IntentRegistry fromCatalog(List<CatalogCommand> rows) {
    final disabled = <VoiceIntentKind>{};
    for (final r in rows) {
      final kind = kindByName(r.intent);
      if (kind != null && !r.enabled) disabled.add(kind);
    }
    return IntentRegistry(_standardIntents(), disabledKinds: disabled);
  }

  /// Map a catalog `intent` string (the enum name, e.g. 'patrol') to its kind.
  static VoiceIntentKind? kindByName(String name) {
    for (final k in VoiceIntentKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }

  /// The default on-device set (also the offline fallback for [fromCatalog]).
  static IntentRegistry get standard => IntentRegistry(_standardIntents());

  /// The code-defined intents in priority order. Safety/interaction control is
  /// checked first (stop wins), then the specific navigation verbs BEFORE the
  /// broad "go to X" matcher, then social / system commands, then persona and
  /// check-in last. [fromCatalog] gates these by the deployment's flags.
  static List<VoiceIntent> _standardIntents() => [
        // 0 — interaction stop; always wins.
        _StopIntent(),
        // 1 — resume a paused reply / motion.
        _KeywordIntent('system.resume', 1, VoiceIntentKind.resume,
            const ['resume', 'carry on', 'keep going', 'continue', 'go on', 'proceed']),
        // 5 — cancel an in-progress navigation. Phrases are kept clear of the
        // stop reflex ("cancel", "never mind", "forget it" are stop synonyms) and
        // of escort's "stay here" — so a bare "cancel"/"stop" still lands on the
        // global safety stop, and only these specific phrases mean "don't go".
        _KeywordIntent('navigation.cancel', 5, VoiceIntentKind.cancelNav, const [
          'abort', 'call it off', 'i changed my mind', 'not anymore',
          "don't take me there", "don't go there", 'go back instead',
        ]),
        // 6 — patrol rounds (spine patrol_start / patrol_stop).
        _RuleIntent('navigation.patrol', 6, VoiceIntentKind.patrol, const [
          (['end patrol', 'end patrolling', 'finish patrol', 'cancel patrol',
            'stop the patrol', 'come back from patrol'], {'action': 'stop'}),
          (['start patrol', 'begin patrol', 'start patrolling', 'do a patrol',
            'patrol the', 'make your rounds', 'start your rounds', 'go on patrol'],
            {'action': 'start'}),
        ]),
        // 7 — escort / follow-me (spine escort_start / escort_stop).
        _RuleIntent('navigation.escort', 7, VoiceIntentKind.escort, const [
          (['end escort', 'you can stay here', 'you can stop following',
            'wait here', 'stay there', "don't follow me anymore"], {'action': 'stop'}),
          (['escort me', 'follow me', 'come with me', 'lead the way', 'guide me',
            'walk me to', 'take me along', 'show me the way'], {'action': 'start'}),
        ]),
        // 8 — sleep / wake the face.
        _RuleIntent('system.sleepWake', 8, VoiceIntentKind.sleepWake, const [
          (['wake up', 'are you awake', 'wake', 'attention'], {'action': 'wake'}),
          (['go to sleep', 'you can sleep', 'take a nap', 'rest now', 'go idle'],
            {'action': 'sleep'}),
        ]),
        // 8 — language switch (extracts the language name).
        _LanguageIntent(),
        // 9 — social gestures (spine wave / reset_body).
        _RuleIntent('social.gesture', 9, VoiceIntentKind.gesture, const [
          (['stand straight', 'reset your posture', 'reset position',
            'straighten up', 'reset your body'], {'gesture': 'reset'}),
          (['wave', 'say hello', 'greet', 'wave hello', 'give a wave',
            'wave at', 'say hi'], {'gesture': 'wave'}),
        ]),
        // 9 — snapshot (spine snapshot).
        _KeywordIntent('social.snapshot', 9, VoiceIntentKind.snapshot, const [
          'take a photo', 'take a picture', 'take a selfie', 'snapshot',
          'capture this', 'take my photo', 'click a photo',
        ]),
        // 9 — teleop drive nudges (spine drive; slot = direction).
        _RuleIntent('social.drive', 9, VoiceIntentKind.drive, const [
          (['go forward', 'move forward', 'move ahead', 'come forward'], {'direction': 'forward'}),
          (['go back', 'move back', 'back up', 'reverse', 'move backward'], {'direction': 'back'}),
          (['turn left', 'go left', 'rotate left'], {'direction': 'left'}),
          (['turn right', 'go right', 'rotate right'], {'direction': 'right'}),
        ]),
        // 9 — playback volume (app-level).
        _RuleIntent('system.volume', 9, VoiceIntentKind.volume, const [
          (['mute', 'be silent', 'silence yourself', 'no sound'], {'action': 'mute'}),
          (['louder', 'speak up', 'turn it up', 'volume up', 'speak louder'], {'action': 'up'}),
          (['quieter', 'turn it down', 'volume down', 'lower the volume',
            'not so loud', 'speak softly'], {'action': 'down'}),
        ]),
        // 9 — capability help ("what can you do").
        _KeywordIntent('system.help', 9, VoiceIntentKind.help, const [
          'what can you do', 'how can you help', 'what are your features',
          'what do you do', 'help me with', 'tell me what you can do',
          'what are you capable of',
        ]),
        // 10 — "take me to <saved point>" and dock (fuzzy, needs nav points).
        _NavIntent(),
        // 20 — persona (rename / voice).
        _PersonaIntent(),
        // 30 — visitor check-in.
        _CheckinIntent(),
      ];
}

/// One row of the spine's voice command catalog, as the robot consumes it.
/// Only the fields the on-device registry needs — the admin/spine hold the rest.
class CatalogCommand {
  const CatalogCommand({
    required this.intent,
    required this.enabled,
    this.examplePhrases = const [],
    this.tier = 'reflex',
  });

  final String intent; // VoiceIntentKind name, e.g. 'patrol'
  final bool enabled;
  final List<String> examplePhrases;
  final String tier; // 'reflex' | 'llm'

  factory CatalogCommand.fromJson(Map<String, dynamic> j) => CatalogCommand(
        intent: (j['intent'] ?? '') as String,
        enabled: (j['enabled'] ?? true) as bool,
        examplePhrases:
            ((j['example_phrases'] ?? const []) as List).map((e) => '$e').toList(),
        tier: (j['tier'] ?? 'reflex') as String,
      );
}

// ── Compact matchers for fixed-phrase commands ───────────────────────────────

/// Fires [kind] with fixed [slots] when any of [phrases] is a substring of the
/// transcript. Substring matching mirrors the existing keyword style; keep
/// phrases specific enough that they don't collide with the broad stop reflex.
class _KeywordIntent implements VoiceIntent {
  _KeywordIntent(this.id, this.priority, this._kind, this._phrases,
      {Map<String, Object?> slots = const {}})
      : _slots = slots;
  @override
  final String id;
  @override
  final int priority;
  final VoiceIntentKind _kind;
  final List<String> _phrases;
  final Map<String, Object?> _slots;

  @override
  IntentMatch? match(String transcript, IntentContext ctx) {
    final lower = transcript.toLowerCase();
    for (final p in _phrases) {
      if (lower.contains(p)) return IntentMatch(_kind, slots: _slots);
    }
    return null;
  }
}

/// Like [_KeywordIntent] but with several (phrases → slots) rules for one kind —
/// e.g. a start/stop pair. First matching rule wins.
class _RuleIntent implements VoiceIntent {
  _RuleIntent(this.id, this.priority, this._kind, this._rules);
  @override
  final String id;
  @override
  final int priority;
  final VoiceIntentKind _kind;
  final List<(List<String>, Map<String, Object?>)> _rules;

  @override
  IntentMatch? match(String transcript, IntentContext ctx) {
    final lower = transcript.toLowerCase();
    for (final (phrases, slots) in _rules) {
      for (final p in phrases) {
        if (lower.contains(p)) return IntentMatch(_kind, slots: slots);
      }
    }
    return null;
  }
}

// ── Intents (thin adapters over the existing matchers) ───────────────────────

/// "stop" / "be quiet" / "that's enough" / "goodbye" — always wins. Mirrors the
/// ambient-face `_stopPhrase` + "≤4 words so 'where is the bus stop' doesn't
/// count" guard, kept identical so behavior is preserved.
class _StopIntent implements VoiceIntent {
  @override
  String get id => 'system.stop';
  @override
  int get priority => 0;

  static final RegExp _stopPhrase = RegExp(
    r'\b(stop|quiet|be quiet|shut up|shush|hush|enough|thats enough|'
    r"that's enough|stop talking|stop speaking|stop it|no more|"
    r'never ?mind|forget it|cancel|goodbye|good bye|bye bye|'
    r'bye|thats all|i am done|im done)\b',
    caseSensitive: false,
  );

  @override
  IntentMatch? match(String transcript, IntentContext ctx) {
    final t = transcript.toLowerCase().trim();
    if (t.isEmpty) return null;
    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (words > 4) return null;
    if (!_stopPhrase.hasMatch(t)) return null;
    return const IntentMatch(VoiceIntentKind.stop);
  }
}

/// "go to <saved point>" and "go to the dock" — delegates to [NavVoice].
class _NavIntent implements VoiceIntent {
  @override
  String get id => 'navigation.goto';
  @override
  int get priority => 10;

  @override
  IntentMatch? match(String transcript, IntentContext ctx) {
    final r = NavVoice.match(transcript, ctx.navPoints);
    if (!r.isCommand) return null;
    if (r.isDock) return const IntentMatch(VoiceIntentKind.dock);
    // Point may be null (a "go to X" with no matching saved point) — carry the
    // heard text so the caller can apologise / list known places, exactly as
    // the current _handleNavVoice does.
    return IntentMatch(
      VoiceIntentKind.navigate,
      slots: {'point': r.point, 'heard': r.heard},
    );
  }
}

/// "change your name to X" / "change your voice to Y" — delegates to [PersonaVoice].
class _PersonaIntent implements VoiceIntent {
  @override
  String get id => 'persona.change';
  @override
  int get priority => 20;

  @override
  IntentMatch? match(String transcript, IntentContext ctx) {
    final r = PersonaVoice.match(transcript);
    if (!r.isCommand) return null;
    return IntentMatch(
      VoiceIntentKind.persona,
      slots: {'personaKind': r.kind, 'personName': r.newName, 'voicePreset': r.preset},
    );
  }
}

/// "I'm here to see <host>" — delegates to [CheckinVoice].
class _CheckinIntent implements VoiceIntent {
  @override
  String get id => 'reception.checkin';
  @override
  int get priority => 30;

  @override
  IntentMatch? match(String transcript, IntentContext ctx) {
    final r = CheckinVoice.match(transcript);
    if (!r.isCommand) return null;
    return IntentMatch(VoiceIntentKind.checkin, slots: {'host': r.hostHeard});
  }
}

/// "speak in Hindi" / "switch to English" / "talk in Tamil" — extracts the
/// language name into the `language` slot. Gated to a known set so "switch to
/// the front desk" doesn't read as a language change; the app maps the name to
/// an ElevenLabs language code.
class _LanguageIntent implements VoiceIntent {
  @override
  String get id => 'system.language';
  @override
  int get priority => 8;

  static final RegExp _cmd = RegExp(
    r'\b(?:speak|talk|respond|reply|switch|change)\b[\w\s]*?\b(?:in|to)\s+([a-z]+)',
    caseSensitive: false,
  );
  static const _known = {
    'english', 'hindi', 'tamil', 'telugu', 'kannada', 'malayalam', 'marathi',
    'bengali', 'gujarati', 'punjabi', 'urdu', 'spanish', 'french', 'german',
    'arabic', 'chinese', 'japanese',
  };

  @override
  IntentMatch? match(String transcript, IntentContext ctx) {
    final m = _cmd.firstMatch(transcript.toLowerCase());
    if (m == null) return null;
    final lang = m.group(1)!;
    if (!_known.contains(lang)) return null;
    return IntentMatch(VoiceIntentKind.language, slots: {'language': lang});
  }
}
