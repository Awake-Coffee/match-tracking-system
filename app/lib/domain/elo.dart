import 'models.dart';

/// Rating every member starts with.
const startingRating = 1000;

/// Upper bound of each rating-difference band in the FIDE expected-score
/// table (Rating Regulations 8.1.2), up to the 400-point cap.
const _fideBandUpperBounds = [
  3, 10, 17, 25, 32, 39, 46, 53, 61, 68, 76, 83, 91, 98, 106, 113, 121, //
  129, 137, 145, 153, 162, 170, 179, 188, 197, 206, 215, 225, 235, 245, //
  256, 267, 278, 290, 302, 315, 328, 344, 357, 374, 391,
];

/// FIDE 8.3.3. Skipped: K = 40 for juniors (no birth dates here).
int fideKFactor(Player player) => player.gamesPlayed < 30
    ? 40
    : player.peakRating < 2400
    ? 20
    : 10;

/// Points [player] gains against [opponent]; [score] is 1, 0.5 or 0.
///
/// Mirrors `public.fide_rating_change` in the Supabase migration; the server
/// is the source of truth and this is only used to preview a result.
int fideRatingChange(Player player, Player opponent, double score) {
  final diff = player.rating - opponent.rating;
  final cappedDiff = diff.abs().clamp(0, 400);
  final bandsPassed = _fideBandUpperBounds
      .where((upper) => upper < cappedDiff)
      .length;
  // Hundredths keep the math exact so FIDE's round-half-up holds.
  final expectedHundredths = 50 + diff.sign * bandsPassed;
  final changeHundredths =
      fideKFactor(player) * ((score * 100).round() - expectedHundredths);
  return ((changeHundredths + 50) / 100).floor();
}
