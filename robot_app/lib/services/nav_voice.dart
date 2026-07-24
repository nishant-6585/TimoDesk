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
  /// heard text (or vice versa), favouring full containment. Tokens match
  /// exactly OR within edit distance 1 for words of 4+ letters — STT regularly
  /// swaps a vowel ("dock" for "Deck Cabin"), and a miss there sends the
  /// visitor to the not-found reply for a point that plainly exists.
  static double _score(String heard, String name) {
    if (heard == name) return 1.0;
    if (heard.contains(name) || name.contains(heard)) return 0.9;
    final ht = heard.split(' ').where((t) => t.isNotEmpty).toList();
    final nt = name.split(' ').where((t) => t.isNotEmpty).toList();
    if (nt.isEmpty) return 0;
    var overlap = 0;
    for (final n in nt) {
      if (ht.any((h) => _tokensMatch(h, n))) overlap++;
    }
    return overlap / nt.length;
  }

  static bool _tokensMatch(String a, String b) {
    if (a == b) return true;
    if (a.length < 4 || b.length < 4) return false;
    return _editDistance(a, b) <= 1;
  }

  static int _editDistance(String a, String b) {
    final m = a.length, n = b.length;
    if ((m - n).abs() > 1) return 2; // early out — we only care about ≤1
    var prev = List<int>.generate(n + 1, (j) => j);
    for (var i = 1; i <= m; i++) {
      final cur = List<int>.filled(n + 1, 0)..[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[n];
  }
}
