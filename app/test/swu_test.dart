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
    final bogdanId = (await repo.swuLadder())
        .firstWhere((p) => p.id != ana.id)
        .id;
    final chessBefore = ana.rating;

    final win = await repo.requestSwuMatch(
      opponentId: bogdanId,
      myGames: 2,
      opponentGames: 1,
    );
    expect(win.awaits(ana.id), isFalse);
    expect(win.scoreFor(bogdanId), '1-2');
    await expectLater(
      repo.respondToSwuMatchRequest(win.id, accept: true),
      throwsA(isA<LadderException>()),
    );

    await repo.signIn(email: bogdanEmail, password: 'x');
    final preview = SwuPreview(
      me: repo.me!,
      opponent: await repo.player(ana.id),
      outcome: Outcome.loss,
    );
    final rated = await repo.respondToSwuMatchRequest(win.id, accept: true);
    expect(rated!.deltaFor(ana.id), 20);
    expect(rated.deltaFor(bogdanId), preview.myDelta);
    expect(preview.myDelta, -20);

    final draw = await repo.requestSwuMatch(
      opponentId: ana.id,
      myGames: 1,
      opponentGames: 1,
    );
    await repo.signIn(email: anaEmail, password: 'x');
    await repo.respondToSwuMatchRequest(draw.id, accept: true);

    final ladder = await repo.swuLadder();
    expect([for (final p in ladder) p.swu.rating], [1018, 982]);
    expect(ladder.first.id, ana.id);
    expect(ladder.first.swu.draws, 1);
    expect(ladder.first.swu.peakRating, 1020);
    expect(ladder.first.rating, chessBefore);

    final history = await repo.swuMatches(playerId: ana.id);
    expect(history.map((m) => m.scoreFor()), ['1-1', '2-1']);
    expect(
      ratingHistory(
        ana.id,
        history.reversed.toList(),
        start: swuStartingRating,
      ),
      [1000, 1020, 1018],
    );
    expect(await repo.swuMatchRequests(), isEmpty);
  });

  test('declined and withdrawn matches are never rated', () async {
    final repo = await anaAndBogdan();
    final anaId = repo.me!.id;
    final bogdanId = (await repo.swuLadder())
        .firstWhere((p) => p.id != anaId)
        .id;

    final withdrawn = await repo.requestSwuMatch(
      opponentId: bogdanId,
      myGames: 2,
      opponentGames: 0,
    );
    expect(
      await repo.respondToSwuMatchRequest(withdrawn.id, accept: false),
      isNull,
    );
    final declined = await repo.requestSwuMatch(
      opponentId: bogdanId,
      myGames: 0,
      opponentGames: 2,
    );
    await repo.signIn(email: bogdanEmail, password: 'x');
    await repo.respondToSwuMatchRequest(declined.id, accept: false);

    expect(await repo.swuMatches(), isEmpty);
    expect(await repo.swuMatchRequests(), isEmpty);
    expect((await repo.player(anaId)).swu.matchesPlayed, 0);
  });

  test('rejects impossible scores and playing yourself', () async {
    final repo = await anaAndBogdan();
    final anaId = repo.me!.id;
    final bogdanId = (await repo.swuLadder())
        .firstWhere((p) => p.id != anaId)
        .id;
    for (final (opponent, mine, theirs) in [
      (anaId, 2, 0),
      (bogdanId, 0, 0),
      (bogdanId, 2, 2),
      (bogdanId, 3, 0),
    ]) {
      await expectLater(
        repo.requestSwuMatch(
          opponentId: opponent,
          myGames: mine,
          opponentGames: theirs,
        ),
        throwsA(isA<LadderException>()),
      );
    }
  });
}
