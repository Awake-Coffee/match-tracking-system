import 'package:awake_ladder/domain/elo.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Player _p(String id, int rating) => Player(
      id: id,
      displayName: id,
      rating: rating,
      gamesPlayed: 0,
      wins: 0,
      losses: 0,
      draws: 0,
      design: 'chalkboard',
    );

void main() {
  group('eloDelta', () {
    // Same cases as supabase/tests/chess_elo_test.sql.
    final cases = <(int, int, double, int)>[
      (1000, 1000, 1, 16),
      (1000, 1000, 0, -16),
      (1000, 1000, 0.5, 0),
      (1200, 1000, 1, 8),
      (1000, 1200, 1, 24),
      (1000, 1200, 0.5, 8),
      (1600, 1000, 1, 1),
    ];
    for (final (a, b, score, expected) in cases) {
      test('$a vs $b scoring $score gains $expected', () {
        expect(eloDelta(a, b, score), expected);
      });
    }

    test('stays within 0..K for a win', () {
      for (var diff = -800; diff <= 800; diff += 25) {
        expect(eloDelta(1000 + diff, 1000, 1), inInclusiveRange(0, kFactor));
      }
    });
  });

  group('MatchPreview', () {
    test('everyone starts at 1000 and a first win is worth 16', () {
      final preview = MatchPreview(
        me: _p('me', startingRating),
        opponent: _p('them', startingRating),
        outcome: Outcome.win,
      );
      expect(preview.myRatingAfter, 1016);
      expect(preview.opponentRatingAfter, 984);
    });

    test('is zero-sum', () {
      for (final outcome in Outcome.values) {
        final preview = MatchPreview(me: _p('a', 1137), opponent: _p('b', 962), outcome: outcome);
        expect(preview.myDelta + preview.opponentDelta, 0);
      }
    });
  });

  test('ratingHistory replays a player through their games', () {
    final m1 = ChessMatch(
      id: 1,
      whiteId: 'a',
      blackId: 'b',
      whiteName: 'A',
      blackName: 'B',
      result: MatchResult.white,
      whiteRatingBefore: 1000,
      blackRatingBefore: 1000,
      ratingDelta: 16,
      playedAt: DateTime(2026),
    );
    final m2 = ChessMatch(
      id: 2,
      whiteId: 'b',
      blackId: 'a',
      whiteName: 'B',
      blackName: 'A',
      result: MatchResult.white,
      whiteRatingBefore: 984,
      blackRatingBefore: 1016,
      ratingDelta: 17,
      playedAt: DateTime(2026),
    );
    expect(ratingHistory('a', [m1, m2]), [1000, 1016, 999]);
    expect(m2.outcomeFor('a'), Outcome.loss);
    expect(m2.colorOf('a'), PieceColor.black);
    expect(m2.winnerId, 'b');
  });
}
