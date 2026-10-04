import 'dart:math' as math;

import 'models.dart';

/// Rating every member starts with on a backgammon ladder (FIBS convention).
const backgammonStartingRating = 1500;

/// Match lengths offered when recording; the database accepts 1 to 25.
const backgammonMatchLengths = [1, 3, 5, 7, 9, 11];

/// Points [player] gains from a match to [matchLength] points (FIBS), which
/// moves newcomers (little [Standing.experience]) faster.
///
/// Mirrors `public.fibs_rating_change` in the Supabase migration; the server
/// is the source of truth and this is only used to preview a result.
int fibsRatingChange(
  Standing player,
  Standing opponent, {
  required bool won,
  required int matchLength,
}) {
  final root = math.sqrt(matchLength);
  final winChance =
      1 / (1 + math.pow(10, (opponent.rating - player.rating) * root / 2000));
  final experienceMultiplier = math.max(1.0, 5 - player.experience / 100);
  return (4 * root * experienceMultiplier * ((won ? 1 : 0) - winChance) + 0.5)
      .floor();
}

/// Whether [scoreA] and [scoreB] can end a match to [matchLength]: exactly
/// one player reached the length.
bool isFinalScore(int matchLength, int scoreA, int scoreB) =>
    math.max(scoreA, scoreB) == matchLength &&
    math.min(scoreA, scoreB) >= 0 &&
    math.min(scoreA, scoreB) < matchLength;
