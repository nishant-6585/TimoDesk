/// checkin_voice.dart — visitor check-in intent matching ("I'm here to see
/// Priya" → host name), plus the fuzzy host lookup and the visitor-name
/// sanitiser for the follow-up "may I have your name?" turn.
///
/// Pure functions only (no I/O) — the dialog state machine lives in
/// ambient_face_screen; the spine calls live in checkin_api.dart.
library;

import 'voice_fuzzy.dart';

/// Outcome of matching a transcript against check-in phrases. Same contract
/// shape as NavVoiceResult: not-a-command / matched with the host text heard.
class CheckinVoiceResult {
  const CheckinVoiceResult._(this.isCommand, this.hostHeard);

  static const CheckinVoiceResult notACommand = CheckinVoiceResult._(false, '');
  const CheckinVoiceResult.heard(this.hostHeard) : isCommand = true;

  final bool isCommand;
  final String hostHeard; // host name as heard, '' when !isCommand
}

/// A staff row as served by spine GET /staff (the fields check-in needs).
class StaffMember {
  final String id;
  final String fullName;
  final String? role;
  const StaffMember({required this.id, required this.fullName, this.role});

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
        id: j['id'] as String,
        fullName: (j['full_name'] ?? '') as String,
        role: j['role'] as String?,
      );
}

class CheckinVoice {
  // "I'm here to see X" / "here to meet X" / "I want to see X" /
  // "I have a meeting with X" / "meeting with X" / "appointment with X".
  // STT drops apostrophes, so "i'm|im|i am" are all tolerated.
  static final List<RegExp> _patterns = [
    RegExp(
      r"\b(?:i\s*'?\s*a?m\s+)?here\s+to\s+(?:see|meet)\s+(?:the\s+)?(.+)$",
      caseSensitive: false,
    ),
    RegExp(
      r"\bi\s+(?:want|would\s+like|'?d\s+like)\s+to\s+(?:see|meet)\s+(?:the\s+)?(.+)$",
      caseSensitive: false,
    ),
    RegExp(
      r"\b(?:i\s+have\s+(?:a\s+|an\s+)?)?(?:meeting|appointment)\s+with\s+(.+)$",
      caseSensitive: false,
    ),
  ];

  static CheckinVoiceResult match(String transcript) {
    final t = transcript.trim();
    for (final p in _patterns) {
      final m = p.firstMatch(t);
      if (m == null) continue;
      final heard = m.group(1)!.trim().replaceAll(RegExp(r'[.?!,]+$'), '');
      if (heard.isEmpty) continue;
      return CheckinVoiceResult.heard(heard);
    }
    return CheckinVoiceResult.notACommand;
  }

  /// Best staff match for the heard host name, or null when nothing scores
  /// ≥ 0.5 (same acceptance bar as nav point matching).
  static StaffMember? bestHost(String heard, List<StaffMember> staff) {
    StaffMember? best;
    double bestScore = 0;
    final h = fuzzyNormalize(heard);
    for (final s in staff) {
      final score = fuzzyScore(h, fuzzyNormalize(s.fullName));
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }
    return bestScore >= 0.5 ? best : null;
  }

  /// Turn the reply to "may I have your name?" into a clean visitor name:
  /// strips lead-ins ("my name is", "i am", "this is"), trailing punctuation,
  /// and title-cases. Returns '' when nothing name-like remains.
  static String extractVisitorName(String transcript) {
    var t = transcript.trim().replaceAll(RegExp(r'[.?!,]+$'), '');
    t = t.replaceFirst(
      RegExp(
        r"^\s*(?:my\s+name\s+is|my\s+name'?s|i\s*'?\s*a?m|this\s+is|it\s*'?s|name\s+is)\s+",
        caseSensitive: false,
      ),
      '',
    );
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty || t.length > 60) return '';
    return t
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// True when the visitor is backing out of the check-in dialog.
  static bool isCancel(String transcript) {
    final t = fuzzyNormalize(transcript);
    return t == 'cancel' ||
        t == 'never mind' ||
        t == 'nevermind' ||
        t == 'no' ||
        t == 'forget it' ||
        t == 'leave it';
  }
}
