import 'modes.dart';

/// Points every member starts with on a Star Wars: Unlimited ladder. No
/// result takes them below it.
const swuStartingRating = 0;

/// Whether a best of three can end with these games won: 2-0, 2-1, 1-0 when
/// time runs out, or 1-1. Mirrors `public.is_valid_score` for 'swu'.
bool isSwuScore(int gamesA, int gamesB) =>
    gamesA >= 0 &&
    gamesA <= 2 &&
    gamesB >= 0 &&
    gamesB <= 2 &&
    gamesA + gamesB >= 1 &&
    gamesA + gamesB <= 3;

/// How a player finished a game of Twin Suns. Once a player is knocked out
/// the final round is played; the one with the most HP at its end wins.
/// [score] is what a result stores for the player.
enum TwinSunsFinish {
  winner(3, 2, 'Winner'),
  survived(2, 1, 'Survived'),
  outInFinalRound(1, 0, 'Out in final round'),
  firstOut(0, -1, 'First out');

  const TwinSunsFinish(this.score, this.points, this.label);

  final int score;
  final int points;
  final String label;

  static TwinSunsFinish of(num score) =>
      values.firstWhere((f) => f.score == score);
}

/// Points an SWU result is worth to a player who scored [score] against a
/// best opponent score of [bestOpponentScore], before the floor at 0: a best
/// of one is +1 / -1, a best of three (and Trilogy) +3 / -1, a draw 0; Twin
/// Suns goes by [TwinSunsFinish]. Mirrors `public.swu_points`.
int swuPoints(
  ResultFormat format,
  int? bestOf,
  num score,
  num bestOpponentScore,
) {
  if (format == ResultFormat.freeForAll) {
    return TwinSunsFinish.of(score).points;
  }
  if (score > bestOpponentScore) return bestOf == 1 ? 1 : 3;
  if (score < bestOpponentScore) return -1;
  return 0;
}
