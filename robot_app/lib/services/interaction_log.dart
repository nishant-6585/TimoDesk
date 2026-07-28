import 'package:flutter/foundation.dart' show debugPrint;

/// interaction_log.dart — the conversation/action LEDGER.
///
/// Every meaningful moment of a human↔robot interaction is appended here as a
/// timestamped event: what the visitor said (each STT path), which handler
/// claimed the utterance, what the robot decided/did (nav dispatch, rename,
/// check-in, apology, greeting), and what it spoke. The ambient screen flushes
/// the buffer to spine `/voice/log` (→ Supabase `conversation`, 7-day DPDP
/// purge) together with the ElevenLabs transcript — one chronological stream
/// per interaction, so "what was said" and "what the robot actually did vs.
/// should have done" can be analysed side by side and the matchers/prompts
/// tuned from real data.
class InteractionLog {
  InteractionLog._();

  static final List<Map<String, dynamic>> _events = [];

  /// Append one event. [kind] is a stable snake_case tag (analysis groups on
  /// it); [detail] is the human-readable specifics.
  ///
  /// Kinds in use: user_utterance_el / user_utterance_vendor_asr /
  /// nav_command / nav_no_match / nav_dispatch_failed / departure / arrival /
  /// persona_rename / persona_voice / persona_voice_unknown / checkin_turn /
  /// greeting / robot_speech / session_started / session_ended /
  /// escort_lost_visitor / escort_arrival_listen.
  static void log(String kind, String detail) {
    _events.add({
      'role': 'action',
      'kind': kind,
      'detail': detail,
      't': DateTime.now().toIso8601String(),
    });
    debugPrint('Ledger: $kind — $detail');
    // Backstop: never grow unbounded if flushes stop happening.
    if (_events.length > 400) _events.removeRange(0, _events.length - 400);
  }

  static bool get isEmpty => _events.isEmpty;

  /// Take everything logged so far (clears the buffer).
  static List<Map<String, dynamic>> drain() {
    final out = List<Map<String, dynamic>>.of(_events);
    _events.clear();
    return out;
  }
}
