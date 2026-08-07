import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';

/// A greeting currently being delivered: the line Mini is saying and, for
/// enrolled staff, who it is for. Any screen can render this.
@immutable
class ActiveGreeting {
  final String text; // on-screen line, e.g. "Hi, Nishant!"
  final String? staffName; // null when the face matched no enrolled staff
  const ActiveGreeting({required this.text, this.staffName});
}

/// Greeting COORDINATOR — the "may we greet this person now?" decision plus the
/// greeting currently on display.
///
/// Lifted out of `AmbientFaceScreen` so the decision lives in ONE place and any
/// screen can render the result. Previously the whole greeting (decision,
/// debounce and overlay) lived inside the ambient screen's State, so while the
/// dashboard was pushed on top a recognized face produced nothing visible
/// anywhere. Speaking + the mic hand-off still belong to the ambient screen —
/// it owns the TTS and the voice session.
class GreetingNotifier extends StateNotifier<ActiveGreeting?> {
  GreetingNotifier() : super(null);

  Timer? _holdTimer;
  final Map<String, DateTime> _greetedAt = {}; // per-staff re-greet debounce
  DateTime? _lastVisitorGreetAt; // unknown faces share one cooldown

  /// Unknown faces can't be told apart, so a global cooldown stands in for the
  /// per-name debounce.
  static const Duration visitorRegreetCooldown = Duration(seconds: 90);
  Duration get _regreetWindow => Duration(minutes: RobotConfig.regreetMinutes);

  /// May we greet [name] right now? Records the greeting when it returns true.
  ///
  /// [busy] means an interaction that OWNS the speaker is in progress —
  /// navigation/escort, a live voice session, or Mini mid-sentence. The
  /// priority rule is unchanged (nav > session > greeting) and nothing is ever
  /// queued or replayed.
  ///
  /// What changed: a blocked greeting is NO LONGER recorded as delivered. The
  /// spine re-emits the same identity every ~5s, so recording it refreshed the
  /// re-greet lockout on every tick — one blocked greeting silenced that person
  /// for as long as the blocking condition held, and a navigation left stale
  /// silenced them permanently. Skipping the record lets a LATER recognition
  /// event greet them once Mini is free.
  bool mayGreetStaff(String name, {required bool busy}) {
    final now = DateTime.now();
    final last = _greetedAt[name];
    if (last != null && now.difference(last) < _regreetWindow) return false;
    if (busy) return false; // deliberately NOT recorded — see above
    _greetedAt[name] = now;
    return true;
  }

  /// May we greet an unrecognised visitor right now? Same rules, one cooldown.
  bool mayGreetVisitor({required bool busy}) {
    if (busy) return false;
    final now = DateTime.now();
    final last = _lastVisitorGreetAt;
    if (last != null && now.difference(last) < visitorRegreetCooldown) {
      return false;
    }
    _lastVisitorGreetAt = now;
    return true;
  }

  /// Publish a greeting for every screen to render; clears itself after [hold].
  void show(String text,
      {String? staffName,
      Duration hold = const Duration(milliseconds: 3500)}) {
    _holdTimer?.cancel();
    state = ActiveGreeting(text: text, staffName: staffName);
    _holdTimer = Timer(hold, () {
      if (mounted) state = null;
    });
  }

  void clear() {
    _holdTimer?.cancel();
    if (mounted) state = null;
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }
}

/// Singleton (kept alive) — the greeting must survive screen changes, which is
/// the whole point of lifting it out of a screen's State.
final greetingProvider =
    StateNotifierProvider<GreetingNotifier, ActiveGreeting?>((ref) {
  ref.keepAlive();
  return GreetingNotifier();
});
