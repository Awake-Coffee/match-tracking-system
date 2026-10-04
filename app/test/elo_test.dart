import 'dart:math' as math;

import 'package:awake_ladder/domain/elo.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Standing _p(String id, int rating, {int gamesPlayed = 0, int? peakRating}) =>
    Standing(
      rating: rating,
      peakRating: peakRating ?? math.max(rating, startingRating),
      played: gamesPlayed,
    );

/// A rated seat for [ratingChanges]: who, which side, what it scored.
({String playerId, int side, num score, Standing standing}) _seat(
  String id,
  int side,
  num score, {
  int rating = startingRating,
  int played = 0,
}) => (
  playerId: id,
  side: side,
  score: score,
  standing: _p(id, rating, gamesPlayed: played),
);

GameResult _chess(
  int id,
  String white,
  String black,
  int whiteBefore,
  int blackBefore,
  int whiteDelta,
) => GameResult(
  id: id,
  mode: GameMode.standardChess,
  seats: [
    RatedSeat(
      playerId: white,
      name: white,
      side: 1,
      score: 1,
      ratingBefore: whiteBefore,
      ratingDelta: whiteDelta,
    ),
    RatedSeat(
      playerId: black,
      name: black,
      side: 2,
      score: 0,
      ratingBefore: blackBefore,
      ratingDelta: -whiteDelta,
    ),
  ],
  recordedBy: white,
  playedAt: DateTime(2026),
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

  group('ratingChanges', () {
    test('everyone starts at 1000 and a first win is worth 20', () {
      expect(
        ratingChanges(MatchType.chess, [
          _seat('me', 1, 1),
          _seat('them', 2, 0),
        ]),
        {'me': 20, 'them': -20},
      );
    });

    test('each player moves by their own K-factor', () {
      expect(
        ratingChanges(MatchType.chess, [
          _seat('me', 1, 1),
          _seat('them', 2, 0, played: 30),
        ]),
        {'me': 20, 'them': -10},
      );
    });

    // Same numbers as supabase/tests/game_modes_test.sql.
    test('a free-for-all averages the change against every opponent', () {
      expect(
        ratingChanges(MatchType.swu, [
          _seat('a', 1, 3),
          _seat('b', 2, 2),
          _seat('c', 3, 0),
          _seat('d', 4, 0),
        ]),
        {'a': 20, 'b': 7, 'c': -13, 'd': -13},
      );
    });

    test('teammates are not each other\'s opponents', () {
      expect(
        ratingChanges(MatchType.chess, [
          _seat('a', 1, 1),
          _seat('b', 1, 1),
          _seat('c', 2, 0),
          _seat('d', 2, 0),
        ]),
        {'a': 20, 'b': 20, 'c': -20, 'd': -20},
      );
    });
  });

  test('ratingHistory replays a player through their games', () {
    final m1 = _chess(1, 'a', 'b', 1000, 1000, 16);
    final m2 = _chess(2, 'b', 'a', 984, 1016, 17);
    expect(ratingHistory('a', [m1, m2], start: startingRating), [
      1000,
      1016,
      999,
    ]);
    expect(m2.outcomeFor('a'), Outcome.loss);
    expect(m2.colorOf('a'), PieceColor.black);
  });
}
