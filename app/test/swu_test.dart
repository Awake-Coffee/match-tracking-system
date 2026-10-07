import 'package:awake_ladder/data/ladder_repository.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:awake_ladder/domain/swu.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ladder_fixture.dart';

void main() {
  test('only best-of-three scores are valid', () {
    for (final (a, b) in [(2, 0), (2, 1), (1, 0), (1, 1), (0, 2), (1, 2)]) {
      expect(isSwuScore(a, b), isTrue, reason: '$a-$b');
    }
    for (final (a, b) in [(0, 0), (2, 2), (3, 0), (-1, 2), (3, 1)]) {
      expect(isSwuScore(a, b), isFalse, reason: '$a-$b');
    }
  });

  // Same numbers as supabase/tests/swu_test.sql.
  test('points: best of one 1/-1, best of three 3/-1, draw 0', () {
    expect(swuPoints(ResultFormat.duel, 1, 1, 0), 1);
    expect(swuPoints(ResultFormat.duel, 1, 0, 1), -1);
    expect(swuPoints(ResultFormat.duel, 3, 2, 1), 3);
    expect(swuPoints(ResultFormat.duel, 3, 0, 2), -1);
    expect(swuPoints(ResultFormat.duel, 3, 1, 1), 0);
    expect([
      for (final f in TwinSunsFinish.values)
        swuPoints(ResultFormat.freeForAll, null, f.score, 3),
    ], [2, 1, 0, -1]);
  });

  ({String playerId, int side, num score, Standing standing}) seat(
    String id,
    int side,
    num score, [
    int rating = 0,
  ]) => (
    playerId: id,
    side: side,
    score: score,
    standing: Standing(rating: rating, peakRating: rating),
  );

  // Same numbers as supabase/tests/game_modes_test.sql.
  test('twin suns points never take a rating below 0', () {
    expect(
      ratingChanges(GameMode.twinSuns, [
        seat('a', 1, 3),
        seat('b', 2, 2),
        seat('c', 3, 1),
        seat('d', 4, 0),
      ]),
      {'a': 2, 'b': 1, 'c': 0, 'd': 0},
    );
    expect(
      ratingChanges(GameMode.twinSuns, [
        seat('a', 1, 0, 2),
        seat('b', 2, 2, 1),
        seat('c', 3, 1),
        seat('d', 4, 3),
      ]),
      {'a': -1, 'b': 1, 'c': 0, 'd': 2},
    );
  });

  test('twin suns needs three or four players, one winner, one out first', () {
    List<SeatReport> seats(List<int> scores) => [
      for (final (i, score) in scores.indexed)
        (playerId: 'p$i', side: i + 1, score: score),
    ];
    expect(invalidResultReason(GameMode.twinSuns, seats([3, 2, 1, 0])), null);
    expect(invalidResultReason(GameMode.twinSuns, seats([0, 3, 2])), null);
    for (final scores in [
      [3, 0],
      [3, 2, 1, 0, 0],
      [3, 3, 0],
      [3, 2, 1],
      [3, 0, 0],
    ]) {
      expect(
        invalidResultReason(GameMode.twinSuns, seats(scores)),
        isNotNull,
        reason: '$scores',
      );
    }
    expect(
      invalidResultReason(GameMode.twinSuns, seats([3, 1, 0]), bestOf: 3),
      isNotNull,
    );
  });

  // Same flow and numbers as supabase/tests/swu_test.sql.
  test('a confirmed match adds SWU points only', () async {
    final repo = await anaAndBogdan();
    final ana = repo.me!;
    final bogdanId = (await repo.ladderIn(GameMode.premier))
        .firstWhere((p) => p.id != ana.id)
        .id;
    final chessBefore = ana.chess.rating;

    final win = await repo.reportSwu(
      opponentId: bogdanId,
      myGames: 2,
      opponentGames: 1,
    );
    expect(win.awaits(ana.id), isFalse);
    expect(win.scoreFor(bogdanId), '1-2');
    expect(win.bestOf, 3);
    await expectLater(
      repo.respondToRequest(win.id, accept: true),
      throwsA(isA<LadderException>()),
    );

    await repo.signIn(email: bogdanEmail, password: 'x');
    final preview = ratingChanges(GameMode.premier, bestOf: 3, [
      for (final s in win.seats)
        (
          playerId: s.playerId,
          side: s.side,
          score: s.score,
          standing: (await repo.player(s.playerId)).swu,
        ),
    ]);
    final rated = await repo.respondToRequest(win.id, accept: true);
    expect(rated!.deltaFor(ana.id), 3);
    expect(rated.deltaFor(bogdanId), preview[bogdanId]);
    expect(preview[bogdanId], 0, reason: 'a loss at 0 stays at 0');

    final draw = await repo.reportSwu(
      opponentId: ana.id,
      myGames: 1,
      opponentGames: 1,
    );
    await repo.signIn(email: anaEmail, password: 'x');
    await repo.respondToRequest(draw.id, accept: true);

    await repo.signIn(email: bogdanEmail, password: 'x');
    final bestOfOne = await repo.reportSwu(
      opponentId: ana.id,
      myGames: 1,
      opponentGames: 0,
      bestOf: 1,
    );
    await repo.signIn(email: anaEmail, password: 'x');
    await repo.respondToRequest(bestOfOne.id, accept: true);

    final ladder = await repo.ladderIn(GameMode.premier);
    expect([for (final p in ladder) p.swu.rating], [2, 1]);
    expect(ladder.first.id, ana.id);
    expect(ladder.first.swu.draws, 1);
    expect(ladder.first.swu.peakRating, 3);
    expect(ladder.first.chess.rating, chessBefore);

    final history = await repo.results(MatchType.swu, playerId: ana.id);
    expect(history.map((m) => m.scoreFor()), ['1-0', '1-1', '2-1']);
    expect(history.first.bestOf, 1);
    expect(
      ratingHistory(
        ana.id,
        history.reversed.toList(),
        start: swuStartingRating,
      ),
      [0, 3, 3, 2],
    );
    expect(await repo.requestsIn(MatchType.swu), isEmpty);
  });

  test('trilogy is its own ladder, always a best of three', () async {
    final repo = await anaAndBogdan();
    final anaId = repo.me!.id;
    final bogdanId = (await repo.ladderIn(GameMode.trilogy))
        .firstWhere((p) => p.id != anaId)
        .id;
    await expectLater(
      repo.reportSwu(
        opponentId: bogdanId,
        myGames: 1,
        opponentGames: 0,
        mode: GameMode.trilogy,
        bestOf: 1,
      ),
      throwsA(isA<LadderException>()),
    );
    final win = await repo.reportSwu(
      opponentId: bogdanId,
      myGames: 2,
      opponentGames: 0,
      mode: GameMode.trilogy,
    );
    await repo.signIn(email: bogdanEmail, password: 'x');
    await repo.respondToRequest(win.id, accept: true);
    expect((await repo.player(anaId)).standingIn(GameMode.trilogy).rating, 3);
    expect((await repo.player(anaId)).swu.played, 0);
  });

  test('declined and withdrawn matches are never rated', () async {
    final repo = await anaAndBogdan();
    final anaId = repo.me!.id;
    final bogdanId = (await repo.ladderIn(GameMode.premier))
        .firstWhere((p) => p.id != anaId)
        .id;

    final withdrawn = await repo.reportSwu(
      opponentId: bogdanId,
      myGames: 2,
      opponentGames: 0,
    );
    expect(await repo.respondToRequest(withdrawn.id, accept: false), isNull);
    final declined = await repo.reportSwu(
      opponentId: bogdanId,
      myGames: 0,
      opponentGames: 2,
    );
    await repo.signIn(email: bogdanEmail, password: 'x');
    await repo.respondToRequest(declined.id, accept: false);

    expect(await repo.results(MatchType.swu), isEmpty);
    expect(await repo.requestsIn(MatchType.swu), isEmpty);
    expect((await repo.player(anaId)).swu.played, 0);
  });

  test('rejects impossible scores and playing yourself', () async {
    final repo = await anaAndBogdan();
    final anaId = repo.me!.id;
    final bogdanId = (await repo.ladderIn(GameMode.premier))
        .firstWhere((p) => p.id != anaId)
        .id;
    for (final (opponent, mine, theirs, bestOf) in [
      (anaId, 2, 0, 3),
      (bogdanId, 0, 0, 3),
      (bogdanId, 2, 2, 3),
      (bogdanId, 3, 0, 3),
      (bogdanId, 2, 0, 1),
      (bogdanId, 1, 1, 1),
      (bogdanId, 2, 0, 2),
    ]) {
      await expectLater(
        repo.reportSwu(
          opponentId: opponent,
          myGames: mine,
          opponentGames: theirs,
          bestOf: bestOf,
        ),
        throwsA(isA<LadderException>()),
        reason: '$mine-$theirs best of $bestOf',
      );
    }
  });
}
