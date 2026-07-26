/// voice_fuzzy.dart — shared fuzzy matching for spoken names/places.
///
/// Extracted from NavVoice so the visitor check-in matcher scores host names
/// with the SAME forgiving rules the nav matcher uses for point names: case/
/// punctuation ignored, token overlap, and edit-distance-1 tolerance on 4+
/// letter words (STT regularly swaps a vowel).
library;

/// Lowercase, strip possessives ("nishant's" → "nishant") and non-alphanumerics.
String fuzzyNormalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r"[''`]s\b"), '')
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Token-overlap score in [0,1]: fraction of [name]'s tokens present in
/// [heard] (exactly, or within edit distance 1 for 4+ letter tokens).
/// Full equality → 1.0, containment either way → 0.9. Inputs must already be
/// [fuzzyNormalize]d.
double fuzzyScore(String heard, String name) {
  if (heard == name) return 1.0;
  if (heard.isEmpty || name.isEmpty) return 0;
  if (heard.contains(name) || name.contains(heard)) return 0.9;
  final ht = heard.split(' ').where((t) => t.isNotEmpty).toList();
  final nt = name.split(' ').where((t) => t.isNotEmpty).toList();
  if (nt.isEmpty) return 0;
  var overlap = 0;
  for (final n in nt) {
    if (ht.any((h) => fuzzyTokensMatch(h, n))) overlap++;
  }
  return overlap / nt.length;
}

bool fuzzyTokensMatch(String a, String b) {
  if (a == b) return true;
  if (a.length < 4 || b.length < 4) return false;
  return _editDistance(a, b) <= 1;
}

int _editDistance(String a, String b) {
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
