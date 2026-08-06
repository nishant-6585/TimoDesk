import '../services/nav_points_api.dart';
import 'voice_fuzzy.dart';

/// Outcome of matching a spoken transcript against navigation commands.
///
/// Three cases the caller must distinguish:
///  • [notACommand] — the transcript isn't a "go to …" phrase at all; let the
///    conversational agent answer normally.
///  • a match with [point] set — navigate there.
///  • a match with [point] null — it WAS a nav command but no saved point fits
///    [heard]; the robot should say so (and list what it knows).
class NavVoiceResult {
  const NavVoiceResult._(this.isCommand, this.point, this.heard, this.isDock);

  static const NavVoiceResult notACommand =
      NavVoiceResult._(false, null, '', false);

  /// The visitor asked Mikee to return to its charging dock. The dock is NOT a
  /// saved point — the SDK goHome/IR-align path owns the approach — so this is
  /// a distinct command with no [point].
  static const NavVoiceResult dockCommand =
      NavVoiceResult._(true, null, 'dock', true);

  const NavVoiceResult.found(NavPoint this.point, this.heard)
      : isCommand = true,
        isDock = false;
  const NavVoiceResult.unknown(this.heard)
      : isCommand = true,
        point = null,
        isDock = false;

  final bool isCommand;
  final NavPoint? point;
  final String heard; // the location text as heard, for the "not found" reply
  final bool isDock; // true → return to the charging dock (goHome), not a point
}

/// Matches transcripts like "go to nishant desk" / "take me to the sofa" /
/// "navigate to reception" against the saved nav points.
///
/// Matching is deliberately forgiving of STT noise: case/punctuation are
/// ignored and the best point is chosen by token overlap, so "nishant's desk"
/// still hits "Nishant Desk". A minimum score keeps "go to the moon" from
/// matching anything.
class NavVoice {
  static final RegExp _command = RegExp(
    r'\b(?:go to|goto|take me to|navigate to|bring me to|walk to)\s+(?:the\s+)?(.+)$',
    caseSensitive: false,
  );

  // "Go to the dock" / "go charge" / "go home" → return to the charging dock.
  // The dock is not a saved point, so these must be caught BEFORE the point
  // matcher (else "dock" fuzzy-matches nothing → "no such place") and before
  // the phrase falls through to the chit-chat agent. Substring match, mirroring
  // the keyword style in VoiceCommandHandler; kept imperative so questions like
  // "where is the charging station?" don't trigger a drive.
  static const List<String> _dockPhrases = [
    'go to the dock', 'go to dock', 'navigate to the dock', 'navigate to dock',
    'return to the dock', 'return to dock', 'back to the dock',
    'go to your dock', 'go to the charger', 'go to the charging station',
    'go charge', 'go and charge', 'go to charge', 'go recharge',
    'go and recharge', 'dock yourself', 'head to the dock', 'come to the dock',
    'go home', 'return home', 'go back home', 'head home',
  ];

  static NavVoiceResult match(String transcript, List<NavPoint> points) {
    final lower = transcript.toLowerCase();
    for (final d in _dockPhrases) {
      if (lower.contains(d)) return NavVoiceResult.dockCommand;
    }

    final m = _command.firstMatch(transcript.trim());
    if (m == null) return NavVoiceResult.notACommand;
    final heard = m.group(1)!.trim().replaceAll(RegExp(r'[.?!,]+$'), '');
    if (heard.isEmpty) return NavVoiceResult.notACommand;

    // Guard: the generic drive commands ("go to sleep", "go forward") are not
    // locations — leave them to the existing keyword command handler.
    const reserved = ['sleep', 'forward', 'back', 'left', 'right', 'home'];
    if (reserved.contains(fuzzyNormalize(heard))) return NavVoiceResult.notACommand;

    NavPoint? best;
    double bestScore = 0;
    for (final p in points) {
      final s = fuzzyScore(fuzzyNormalize(heard), fuzzyNormalize(p.name));
      if (s > bestScore) {
        bestScore = s;
        best = p;
      }
    }
    if (best != null && bestScore >= 0.5) {
      return NavVoiceResult.found(best, heard);
    }
    return NavVoiceResult.unknown(heard);
  }
}
