import 'dart:math' as math;

/// Rating every member starts with.
const startingRating = 1000;

/// K-factor applied to every game (see spec clarifications).
const kFactor = 32;

/// Points player A gains against player B.
///
/// [score] is 1 for a win, 0.5 for a draw and 0 for a loss. Player B always
/// receives the negative of this value, so the ladder stays zero-sum.
///
/// Mirrors `public.elo_delta` in the Supabase migration; the server is the
/// source of truth and this is only used to preview a result.
int eloDelta(int ratingA, int ratingB, double score, {int k = kFactor}) {
  final expected = 1 / (1 + math.pow(10, (ratingB - ratingA) / 400));
  return (k * (score - expected)).round();
}
