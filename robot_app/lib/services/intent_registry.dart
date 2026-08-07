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

/// The kind of on-device command a transcript resolved to.
enum VoiceIntentKind { stop, navigate, dock, persona, checkin }

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
  IntentRegistry(List<VoiceIntent> intents)
      : _intents = List.unmodifiable(
          [...intents]..sort((a, b) => a.priority.compareTo(b.priority)),
        );

  final List<VoiceIntent> _intents;

  /// The intents in dispatch order — exposed for tests / an admin view.
  List<VoiceIntent> get intents => _intents;

  /// Resolve [transcript] to a command, or null for "let the agent answer".
  IntentMatch? match(String transcript, [IntentContext ctx = const IntentContext()]) {
    for (final intent in _intents) {
      final m = intent.match(transcript, ctx);
      if (m != null) return m;
    }
    return null;
  }

  /// The default on-device set, in the historical ambient-face order:
  /// stop → navigation/dock → persona → check-in.
  static IntentRegistry get standard => IntentRegistry([
        _StopIntent(),
        _NavIntent(),
        _PersonaIntent(),
        _CheckinIntent(),
      ]);
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
