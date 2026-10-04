import 'package:awake_ladder/domain/backgammon.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Player _p(String id, int rating, {int experience = 0}) => Player(
  id: id,
  displayName: id,
  rating: 1000,
  peakRating: 1000,
  gamesPlayed: 0,
  wins: 0,
  losses: 0,
  draws: 0,
  backgammon: BackgammonStats(
    rating: rating,
    peakRating: rating,
    experience: experience,
  ),
);

void main() {
  group('fibsRatingChange', () {
    // Same cases as supabase/tests/backgammon_test.sql.
    final cases = <(int, int, int, int, bool, int)>[
      (1500, 0, 1500, 5, true, 22),
      (1500, 0, 1500, 5, false, -22),
      (1500, 0, 1500, 11, true, 33),
      (1500, 500, 1500, 1, true, 2),
      (1563, 90, 1684, 5, true, 21),
      (1684, 214, 1563, 5, false, -15),
      (1700, 400, 1500, 5, true, 3),
      (1500, 400, 1700, 5, true, 6),
    ];
    for (final (rating, experience, opponent, length, won, expected) in cases) {
      test('$rating with $experience experience vs $opponent, '
          '${won ? 'winning' : 'losing'} to $length: $expected', () {
        expect(
          fibsRatingChange(
            BackgammonStats(rating: rating, experience: experience),
            BackgammonStats(rating: opponent),
            won: won,
            matchLength: length,
          ),
          expected,
        );
      });
    }
  });

  test('preview moves each player by their own experience', () {
    final preview = BackgammonPreview(
      me: _p('me', 1500),
      opponent: _p('them', 1500, experience: 400),
      won: true,
      matchLength: 5,
    );
    expect(preview.myDelta, 22);
    expect(preview.opponentDelta, -4);
  });

  test('a final score has exactly one player at the match length', () {
    expect(isFinalScore(5, 5, 3), isTrue);
    expect(isFinalScore(5, 0, 5), isTrue);
    expect(isFinalScore(5, 5, 5), isFalse);
    expect(isFinalScore(5, 4, 3), isFalse);
    expect(isFinalScore(5, 6, 3), isFalse);
  });

  test('ratingHistory starts a backgammon line at 1500', () {
    final match = BackgammonMatch(
      id: 1,
      winnerId: 'a',
      loserId: 'b',
      winnerName: 'A',
      loserName: 'B',
      matchLength: 5,
      loserScore: 3,
      winnerRatingBefore: 1500,
      loserRatingBefore: 1500,
      winnerRatingDelta: 22,
      loserRatingDelta: -22,
      playedAt: DateTime(2026),
    );
    expect(ratingHistory('b', [match]), [1500, 1478]);
    expect(ratingHistory('a', [], start: backgammonStartingRating), [1500]);
    expect(match.scoreFor('b'), '3-5');
    expect(match.scoreFor(), '5-3');
  });
}
