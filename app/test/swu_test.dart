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

  // Same flow and numbers as supabase/tests/swu_test.sql.
  test('a confirmed match moves SWU ratings only', () async {
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
    await expectLater(
      repo.respondToRequest(win.id, accept: true),
      throwsA(isA<LadderException>()),
    );

    await repo.signIn(email: bogdanEmail, password: 'x');
    final preview = ratingChanges(MatchType.swu, [
      for (final s in win.seats)
        (
          playerId: s.playerId,
          side: s.side,
          score: s.score,
          standing: (await repo.player(s.playerId)).swu,
        ),
    ]);
    final rated = await repo.respondToRequest(win.id, accept: true);
    expect(rated!.deltaFor(ana.id), 20);
    expect(rated.deltaFor(bogdanId), preview[bogdanId]);
    expect(preview[bogdanId], -20);

    final draw = await repo.reportSwu(
      opponentId: ana.id,
      myGames: 1,
      opponentGames: 1,
    );
    await repo.signIn(email: anaEmail, password: 'x');
    await repo.respondToRequest(draw.id, accept: true);

    final ladder = await repo.ladderIn(GameMode.premier);
    expect([for (final p in ladder) p.swu.rating], [1018, 982]);
    expect(ladder.first.id, ana.id);
    expect(ladder.first.swu.draws, 1);
    expect(ladder.first.swu.peakRating, 1020);
    expect(ladder.first.chess.rating, chessBefore);

    final history = await repo.results(MatchType.swu, playerId: ana.id);
    expect(history.map((m) => m.scoreFor()), ['1-1', '2-1']);
    expect(
      ratingHistory(
        ana.id,
        history.reversed.toList(),
        start: swuStartingRating,
      ),
      [1000, 1020, 1018],
    );
    expect(await repo.requestsIn(MatchType.swu), isEmpty);
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
    for (final (opponent, mine, theirs) in [
      (anaId, 2, 0),
      (bogdanId, 0, 0),
      (bogdanId, 2, 2),
      (bogdanId, 3, 0),
    ]) {
      await expectLater(
        repo.reportSwu(
          opponentId: opponent,
          myGames: mine,
          opponentGames: theirs,
        ),
        throwsA(isA<LadderException>()),
      );
    }
  });
}
