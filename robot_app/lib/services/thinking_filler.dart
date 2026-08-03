/// Filler lines spoken the moment a question is accepted, while the grounded
/// brain (embed → pgvector → Claude) is still working.
///
/// Blueprint §08: the FAQ fast-path answers in under ~1.5s, but a Claude
/// fallback takes 2-4s — long enough that silence reads as "the robot is
/// broken". Speaking immediately covers that window, so perceived latency is
/// the filler's start, not the answer's.
///
/// Rotating rather than fixed: the same sentence every time is worse than
/// silence once a visitor hears it twice.
library;

class ThinkingFiller {
  ThinkingFiller._();

  /// Kept short (~1-1.5s spoken) so a fast FAQ answer isn't left queued behind
  /// a long filler, and phrased so it still reads naturally if the answer
  /// lands almost immediately.
  static const List<String> phrases = [
    'Good question — let me check that for you.',
    'One moment while I look that up.',
    'Let me find that for you.',
    'Just a second — checking now.',
  ];

  static int _next = 0;

  /// Next filler in rotation. Deterministic round-robin (not random) so the
  /// same line never repeats back-to-back.
  static String next() {
    final phrase = phrases[_next % phrases.length];
    _next++;
    return phrase;
  }

  /// Test seam — reset the rotation.
  static void reset() => _next = 0;
}
