import 'package:awake_ladder/domain/backgammon.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Standing _p(int rating, {int experience = 0}) =>
    Standing(rating: rating, peakRating: rating, experience: experience);

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
            _p(rating, experience: experience),
            _p(opponent),
            won: won,
            matchLength: length,
          ),
          expected,
        );
      });
    }
  });

  test('preview moves each player by their own experience', () {
    expect(
      ratingChanges(MatchType.backgammon, [
        (playerId: 'me', side: 1, score: 5, standing: _p(1500)),
        (
          playerId: 'them',
          side: 2,
          score: 0,
          standing: _p(1500, experience: 400),
        ),
      ]),
      {'me': 22, 'them': -4},
    );
  });

  // Same numbers as supabase/tests/game_modes_test.sql.
  test('a chouette box plays each team member', () {
    expect(
      ratingChanges(MatchType.backgammon, [
        (playerId: 'box', side: 1, score: 3, standing: _p(1500)),
        for (final id in ['a', 'b', 'c'])
          (playerId: id, side: 2, score: 5, standing: _p(1500)),
      ]),
      {'box': -22, 'a': 22, 'b': 22, 'c': 22},
    );
  });

  test('a final score has exactly one player at the match length', () {
    expect(isFinalScore(5, 5, 3), isTrue);
    expect(isFinalScore(5, 0, 5), isTrue);
    expect(isFinalScore(5, 5, 5), isFalse);
    expect(isFinalScore(5, 4, 3), isFalse);
    expect(isFinalScore(5, 6, 3), isFalse);
  });

  test('ratingHistory starts a backgammon line at 1500', () {
    final match = GameResult(
      id: 1,
      mode: GameMode.standardBackgammon,
      seats: const [
        RatedSeat(
          playerId: 'a',
          name: 'A',
          side: 1,
          score: 5,
          ratingBefore: 1500,
          ratingDelta: 22,
        ),
        RatedSeat(
          playerId: 'b',
          name: 'B',
          side: 2,
          score: 3,
          ratingBefore: 1500,
          ratingDelta: -22,
        ),
      ],
      recordedBy: 'a',
      playedAt: DateTime(2026),
    );
    expect(ratingHistory('b', [match], start: backgammonStartingRating), [
      1500,
      1478,
    ]);
    expect(ratingHistory('a', [], start: backgammonStartingRating), [1500]);
    expect(match.scoreFor('b'), '3-5');
    expect(match.scoreFor(), '5-3');
  });
}
