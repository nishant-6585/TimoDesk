import '../services/nav_points_api.dart';

/// Outcome of matching a spoken transcript against navigation commands.
///
/// Three cases the caller must distinguish:
///  • [notACommand] — the transcript isn't a "go to …" phrase at all; let the
///    conversational agent answer normally.
///  • a match with [point] set — navigate there.
///  • a match with [point] null — it WAS a nav command but no saved point fits
///    [heard]; the robot should say so (and list what it knows).
class NavVoiceResult {
  const NavVoiceResult._(this.isCommand, this.point, this.heard);

  static const NavVoiceResult notACommand =
      NavVoiceResult._(false, null, '');

  const NavVoiceResult.found(NavPoint this.point, this.heard)
      : isCommand = true;
  const NavVoiceResult.unknown(this.heard)
      : isCommand = true,
        point = null;

  final bool isCommand;
  final NavPoint? point;
  final String heard; // the location text as heard, for the "not found" reply
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

  static NavVoiceResult match(String transcript, List<NavPoint> points) {
    final m = _command.firstMatch(transcript.trim());
    if (m == null) return NavVoiceResult.notACommand;
    final heard = m.group(1)!.trim().replaceAll(RegExp(r'[.?!,]+$'), '');
    if (heard.isEmpty) return NavVoiceResult.notACommand;

    // Guard: the generic drive commands ("go to sleep", "go forward") are not
    // locations — leave them to the existing keyword command handler.
    const reserved = ['sleep', 'forward', 'back', 'left', 'right', 'home'];
    if (reserved.contains(_normalize(heard))) return NavVoiceResult.notACommand;

    NavPoint? best;
    double bestScore = 0;
    for (final p in points) {
      final s = _score(_normalize(heard), _normalize(p.name));
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

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"[''`]s\b"), '') // "nishant's" → "nishant"
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Token-overlap score: fraction of the point-name's tokens present in the
  /// heard text (or vice versa), favouring full containment.
  static double _score(String heard, String name) {
    if (heard == name) return 1.0;
    if (heard.contains(name) || name.contains(heard)) return 0.9;
    final ht = heard.split(' ').toSet();
    final nt = name.split(' ').toSet();
    if (nt.isEmpty) return 0;
    final overlap = ht.intersection(nt).length;
    return overlap / nt.length;
  }
}
