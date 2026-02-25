// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Fuzzy variant duplicate check
// ─────────────────────────────────────────────

import 'package:string_similarity/string_similarity.dart';
import '../models/models.dart';
import 'text_normalization.dart';

/// Similarity threshold: >= this value is considered a duplicate (0–1).
const double kFuzzyDuplicateThreshold = 0.85;

/// Returns the first existing variant whose fullLabel is fuzzy-similar to [candidate]'s, or null.
/// Uses accent-normalized labels so "Café" and "Cafe" match.
Variant? findFuzzyDuplicateVariant(Variant candidate, List<Variant> existing) {
  if (existing.isEmpty) return null;
  final candidateLabel = candidate.fullLabel;
  if (candidateLabel.isEmpty) return null;
  final normCandidate = normalizeAccents(candidateLabel.toLowerCase());
  Variant? bestMatch;
  double bestScore = 0.0;
  for (final v in existing) {
    final normExisting = normalizeAccents(v.fullLabel.toLowerCase());
    final score = StringSimilarity.compareTwoStrings(normCandidate, normExisting);
    if (score >= kFuzzyDuplicateThreshold && score > bestScore) {
      bestScore = score;
      bestMatch = v;
    }
  }
  return bestMatch;
}
