import 'dart:math' as math;

import 'package:awake_ladder/domain/elo.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Player _p(String id, int rating, {int gamesPlayed = 0, int? peakRating}) =>
    Player(
      id: id,
      displayName: id,
      rating: rating,
      peakRating: peakRating ?? math.max(rating, startingRating),
      gamesPlayed: gamesPlayed,
      wins: 0,
      losses: 0,
      draws: 0,
    );

void main() {
  group('fideRatingChange', () {
    // Same cases as supabase/tests/chess_elo_test.sql.
    final cases = <(int, int, int, double, int)>[
      (1000, 0, 1000, 1, 20),
      (1000, 0, 1000, 0, -20),
      (1000, 0, 1000, 0.5, 0),
      (1200, 0, 1000, 1, 10),
      (1000, 0, 1200, 1, 30),
      (1000, 0, 1200, 0.5, 10),
      (1000, 30, 1000, 1, 10),
      (1600, 30, 1000, 1, 2),
      (2400, 30, 2400, 1, 5),
      (2435, 30, 2400, 1, 5),
      (2435, 30, 2400, 0, -5),
    ];
    for (final (rating, games, opponentRating, score, expected) in cases) {
      test('$rating after $games games vs $opponentRating scoring $score '
          'gains $expected', () {
        expect(
          fideRatingChange(
            _p('a', rating, gamesPlayed: games),
            _p('b', opponentRating),
            score,
          ),
          expected,
        );
      });
    }

    test('K stays 10 after dropping below 2400', () {
      expect(
        fideRatingChange(
          _p('a', 2300, gamesPlayed: 30, peakRating: 2400),
          _p('b', 2300),
          1,
        ),
        5,
      );
    });

    test('stays within 0..K for a win', () {
      for (var diff = -800; diff <= 800; diff += 25) {
        expect(
          fideRatingChange(_p('a', 1000 + diff), _p('b', 1000), 1),
          inInclusiveRange(0, 40),
        );
      }
    });
  });

  group('MatchPreview', () {
    test('everyone starts at 1000 and a first win is worth 20', () {
      final preview = MatchPreview(
        me: _p('me', startingRating),
        opponent: _p('them', startingRating),
        outcome: Outcome.win,
      );
      expect(preview.myRatingAfter, 1020);
      expect(preview.opponentRatingAfter, 980);
    });

    test('each player moves by their own K-factor', () {
      final preview = MatchPreview(
        me: _p('me', startingRating),
        opponent: _p('them', startingRating, gamesPlayed: 30),
        outcome: Outcome.win,
      );
      expect(preview.myDelta, 20);
      expect(preview.opponentDelta, -10);
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
      whiteRatingDelta: 16,
      blackRatingDelta: -16,
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
      whiteRatingDelta: 17,
      blackRatingDelta: -17,
      playedAt: DateTime(2026),
    );
    expect(ratingHistory('a', [m1, m2]), [1000, 1016, 999]);
    expect(m2.outcomeFor('a'), Outcome.loss);
    expect(m2.colorOf('a'), PieceColor.black);
    expect(m2.winnerId, 'b');
  });
}
