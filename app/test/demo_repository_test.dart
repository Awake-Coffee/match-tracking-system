import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/domain/backgammon.dart';
import 'package:awake_ladder/data/ladder_repository.dart';
import 'package:awake_ladder/domain/elo.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ladder_fixture.dart';

void main() {
  test('a new ladder starts empty', () async {
    expect(
      await DemoLadderRepository().ladderIn(GameMode.standardChess),
      isEmpty,
    );
  });

  test('ladder replays from history', () async {
    final repo = await anaAndBogdan();
    final players = await repo.ladderIn(GameMode.standardChess);

    for (final p in players) {
      final games = await repo.results(
        MatchType.chess,
        playerId: p.id,
        limit: 1000,
      );
      expect(games.length, p.chess.played);
      expect(p.chess.wins + p.chess.losses + p.chess.draws, p.chess.played);
      final history = ratingHistory(
        p.id,
        games.reversed.toList(),
        start: startingRating,
      );
      expect(history.first, startingRating);
      expect(history.last, p.chess.rating);
    }
  });

  test('deleting an account keeps confirmed results under its name', () async {
    final repo = await anaAndBogdan();
    final ana = repo.me!;
    await repo.deleteAccount();
    expect(repo.isSignedIn, isFalse);

    // Ana is off the ladder and her login is gone, but Bogdan keeps the
    // rating her game gave him and still sees the game against "Ana".
    expect(
      (await repo.ladderIn(GameMode.standardChess)).map((p) => p.displayName),
      ['Bogdan'],
    );
    await repo.signIn(email: bogdanEmail, password: 'x');
    final bogdan = repo.me!;
    final games = await repo.results(MatchType.chess, playerId: bogdan.id);
    expect(games, hasLength(1));
    expect(games.single.opponentsOf(bogdan.id).single.name, 'Ana');
    expect(games.single.opponentsOf(bogdan.id).single.playerId, ana.id);
    expect(bogdan.chess.rating, lessThan(startingRating));
    // What was waiting on her answer went with her.
    expect(await repo.requestsIn(MatchType.chess), isEmpty);
    await expectLater(repo.player(ana.id), throwsA(isA<LadderException>()));
  });

  test('a deleted member\'s results keep the name they had last', () async {
    final repo = await anaAndBogdan();
    await repo.updateDisplayName('Ana Maria');
    await repo.deleteAccount();

    await repo.signIn(email: bogdanEmail, password: 'x');
    final games = await repo.results(MatchType.chess);
    expect(games.single.opponentsOf(repo.me!.id).single.name, 'Ana Maria');
  });

  test('a sign-up after a deletion leaves the other members alone', () async {
    final repo = await anaAndBogdan();
    await repo.signIn(email: bogdanEmail, password: 'x');
    final bogdan = repo.me!;
    await repo.signIn(email: anaEmail, password: 'x');
    await repo.deleteAccount();

    await repo.signUp(
      email: 'cleo@example.com',
      password: 'x',
      displayName: 'Cleo',
    );
    expect(repo.me!.id, isNot(bogdan.id));
    final ladder = await repo.ladderIn(GameMode.standardChess);
    expect(
      ladder.map((p) => p.displayName),
      unorderedEquals(['Bogdan', 'Cleo']),
    );
    final kept = ladder.firstWhere((p) => p.id == bogdan.id);
    expect(kept.displayName, 'Bogdan');
    expect(kept.chess.rating, bogdan.chess.rating);
    expect(kept.chess.played, bogdan.chess.played);
  });

  test('deleting an account needs a signed-in member', () async {
    await expectLater(
      DemoLadderRepository().deleteAccount(),
      throwsA(isA<LadderException>()),
    );
  });

  test('ladder is sorted by rating, then games, then name', () async {
    final players = await (await anaAndBogdan()).ladderIn(
      GameMode.standardChess,
    );
    for (var i = 1; i < players.length; i++) {
      final above = players[i - 1].chess;
      final below = players[i].chess;
      expect(
        above.rating > below.rating ||
            above.rating == below.rating && above.played >= below.played,
        isTrue,
      );
    }
  });

  test('sign-up reports whether the member is signed in', () async {
    final repo = DemoLadderRepository();
    expect(
      await repo.signUp(
        email: 'a@example.com',
        password: 'x',
        displayName: 'A',
      ),
      SignUpResult.signedIn,
    );
    expect(repo.isSignedIn, isTrue);
    await repo.signOut();

    repo.requireEmailConfirmation = true;
    expect(
      await repo.signUp(
        email: 'b@example.com',
        password: 'x',
        displayName: 'B',
      ),
      SignUpResult.confirmationSent,
    );
    expect(repo.isSignedIn, isFalse);
    await repo.signIn(email: 'b@example.com', password: 'x');
    expect(repo.me!.displayName, 'B');
  });

  test('a reported game is rated only once the opponent confirms', () async {
    final repo = DemoLadderRepository();
    await repo.signUp(
      email: 'bo@example.com',
      password: 'password',
      displayName: 'Bo',
    );
    final bo = repo.me!;
    await repo.signOut();
    await repo.signUp(
      email: 'ana@example.com',
      password: 'password',
      displayName: 'Ana',
    );
    final ana = repo.me!;
    expect(ana.chess.rating, 1000);

    final request = await repo.reportChess(
      opponentId: bo.id,
      myColor: PieceColor.black,
      myOutcome: Outcome.win,
      clock: const ClockSetting(TimeControl.fischer5plus3),
    );
    expect(request.colorOf(ana.id), PieceColor.black);
    expect(request.outcomeFor(ana.id), Outcome.win);
    expect(request.awaits(ana.id), isFalse);
    expect(repo.me!.chess.rating, 1000);
    expect(await repo.results(MatchType.chess), isEmpty);
    await expectLater(
      repo.respondToRequest(request.id, accept: true),
      throwsA(isA<LadderException>()),
    );

    await repo.signIn(email: 'bo@example.com', password: 'password');
    final pending = await repo.requestsIn(MatchType.chess);
    expect(pending.single.awaits(bo.id), isTrue);
    final revision = repo.revision;
    final match = await repo.respondToRequest(request.id, accept: true);

    expect(match!.deltaFor(ana.id), 20);
    expect(match.clock!.preset, TimeControl.fischer5plus3);
    expect(repo.me!.chess.rating, 980);
    expect((await repo.player(ana.id)).chess.rating, 1020);
    expect(await repo.requestsIn(MatchType.chess), isEmpty);
    expect(repo.revision, greaterThan(revision));
  });

  test('declined and withdrawn games are never rated', () async {
    final repo = await anaAndBogdan();
    final ana = repo.me!;
    final incoming = (await repo.requestsIn(MatchType.chess)).single;
    expect(incoming.awaits(ana.id), isTrue);
    expect(await repo.respondToRequest(incoming.id, accept: false), isNull);

    final mine = await repo.reportChess(
      opponentId: incoming.opponentsOf(ana.id).single.playerId,
      myColor: PieceColor.white,
      myOutcome: Outcome.draw,
      clock: const ClockSetting(TimeControl.sudden5),
    );
    expect(await repo.respondToRequest(mine.id, accept: false), isNull);

    expect(await repo.requestsIn(MatchType.chess), isEmpty);
    expect(repo.me!.chess.rating, ana.chess.rating);
    expect(repo.me!.chess.played, ana.chess.played);
  });

  test(
    'a declined game stays for the reporter until they dismiss it',
    () async {
      final repo = await anaAndBogdan();
      final ana = repo.me!;
      final request = (await repo.requestsIn(MatchType.chess)).single;
      final bogdanId = request.requestedBy;
      await repo.respondToRequest(request.id, accept: false);

      // The decliner has nothing left to answer and can't answer it again.
      expect(await repo.requestsIn(MatchType.chess), isEmpty);
      await expectLater(
        repo.respondToRequest(request.id, accept: false),
        throwsA(isA<LadderException>()),
      );
      await expectLater(
        repo.dismissRequest(request.id),
        throwsA(isA<LadderException>()),
      );

      await repo.signIn(email: bogdanEmail, password: 'x');
      final declined = (await repo.requestsIn(MatchType.chess)).single;
      expect(declined.status, RequestStatus.declined);
      expect(declined.respondedAt, isNotNull);
      expect(declined.declinedFor(bogdanId), isTrue);
      expect(declined.awaits(bogdanId), isFalse);
      expect(declined.awaits(ana.id), isFalse);
      await expectLater(
        repo.respondToRequest(request.id, accept: true),
        throwsA(isA<LadderException>()),
        reason: 'a declined game can no longer be confirmed',
      );

      await repo.dismissRequest(request.id);
      expect(await repo.requestsIn(MatchType.chess), isEmpty);
      expect((await repo.player(ana.id)).chess.rating, ana.chess.rating);
    },
  );

  test(
    'a declined backgammon or SWU match is dismissed the same way',
    () async {
      final repo = await anaAndBogdanWithSwu();
      final bgRequest = (await repo.requestsIn(MatchType.backgammon)).single;
      final swuRequest = (await repo.requestsIn(MatchType.swu)).single;
      await repo.respondToRequest(bgRequest.id, accept: false);
      await repo.respondToRequest(swuRequest.id, accept: false);
      expect(await repo.requestsIn(MatchType.backgammon), isEmpty);
      expect(await repo.requestsIn(MatchType.swu), isEmpty);

      await repo.signIn(email: bogdanEmail, password: 'x');
      final bogdanId = repo.me!.id;
      final bg = (await repo.requestsIn(MatchType.backgammon)).single;
      final swu = (await repo.requestsIn(MatchType.swu)).single;
      expect(bg.declinedFor(bogdanId) && !bg.awaits(bogdanId), isTrue);
      expect(swu.declinedFor(bogdanId) && !swu.awaits(bogdanId), isTrue);

      await repo.dismissRequest(bg.id);
      await repo.dismissRequest(swu.id);
      expect(await repo.requestsIn(MatchType.backgammon), isEmpty);
      expect(await repo.requestsIn(MatchType.swu), isEmpty);
      await expectLater(
        repo.dismissRequest(swu.id),
        throwsA(isA<LadderException>()),
      );
    },
  );

  test('a pending game can only be withdrawn, not dismissed', () async {
    final repo = await anaAndBogdan();
    final ana = repo.me!;
    final mine = await repo.reportChess(
      opponentId: (await repo.requestsIn(MatchType.chess)).single.requestedBy,
      myColor: PieceColor.white,
      myOutcome: Outcome.win,
      clock: const ClockSetting(TimeControl.sudden5),
    );
    await expectLater(
      repo.dismissRequest(mine.id),
      throwsA(isA<LadderException>()),
    );
    await repo.respondToRequest(mine.id, accept: false);
    expect(
      (await repo.requestsIn(MatchType.chess))
          .where((r) => r.requestedBy == ana.id),
      isEmpty,
      reason: 'withdrawing deletes outright',
    );
  });

  test('custom presets need the time the players set', () async {
    final repo = await anaAndBogdan();
    final opponentId = (await repo.ladderIn(GameMode.standardChess))
        .firstWhere((p) => p.id != repo.me!.id)
        .id;
    Future<ResultRequest> request(ClockSetting clock) => repo.reportChess(
      opponentId: opponentId,
      myColor: PieceColor.white,
      myOutcome: Outcome.win,
      clock: clock,
    );

    for (final incomplete in const [
      ClockSetting(TimeControl.fischerCustom, customBaseMinutes: 7),
      ClockSetting(TimeControl.suddenCustom),
      ClockSetting(TimeControl.fischer3plus2, customBaseMinutes: 7),
    ]) {
      await expectLater(request(incomplete), throwsA(isA<LadderException>()));
    }

    final sent = await request(
      const ClockSetting(
        TimeControl.fischerCustom,
        customBaseMinutes: 7,
        customExtraSeconds: 4,
      ),
    );
    expect(sent.clock!.label, 'Fischer 7 min + 4 s');
    expect(
      const ClockSetting(
        TimeControl.hourglassCustom,
        customBaseMinutes: 2,
      ).label,
      'Hourglass 2 min',
    );
  });

  test('rejects playing yourself and duplicate names', () async {
    final repo = DemoLadderRepository();
    await repo.signUp(
      email: 'a@example.com',
      password: 'password',
      displayName: 'Ana',
    );
    final me = repo.me!;
    await expectLater(
      repo.reportChess(
        opponentId: me.id,
        myColor: PieceColor.white,
        myOutcome: Outcome.win,
        clock: const ClockSetting(TimeControl.sudden5),
      ),
      throwsA(isA<LadderException>()),
    );
    await repo.signOut();
    await repo.signUp(
      email: 'b@example.com',
      password: 'password',
      displayName: 'ana',
    );
    expect(repo.me!.displayName, 'ana 2');
    await expectLater(
      repo.updateDisplayName('ANA'),
      throwsA(isA<LadderException>()),
    );
  });

  test(
    'a backgammon match is rated once confirmed, apart from chess',
    () async {
      final repo = await anaAndBogdan();
      final ana = repo.me!;
      final bogdan = (await repo.ladderIn(GameMode.standardChess))
          .firstWhere((p) => p.id != ana.id);
      expect(ana.backgammon.rating, backgammonStartingRating);

      final request = await repo.reportBackgammon(
        opponentId: bogdan.id,
        myScore: 3,
        opponentScore: 5,
      );
      expect(request.outcomeFor(bogdan.id), Outcome.win);
      expect(request.scoreFor(), '5-3');
      expect(await repo.results(MatchType.backgammon), isEmpty);
      await expectLater(
        repo.respondToRequest(request.id, accept: true),
        throwsA(isA<LadderException>()),
      );

      await repo.signIn(email: bogdanEmail, password: 'x');
      final match = await repo.respondToRequest(request.id, accept: true);
      expect(match!.deltaFor(bogdan.id), 22);
      expect(match.deltaFor(ana.id), -22);

      final players = {
        for (final p in await repo.ladderIn(GameMode.standardBackgammon))
          p.id: p,
      };
      expect(players[bogdan.id]!.backgammon.rating, 1522);
      expect(players[bogdan.id]!.backgammon.experience, 5);
      expect(players[ana.id]!.backgammon.rating, 1478);
      expect(players[ana.id]!.backgammon.losses, 1);
      expect(
        players[ana.id]!.chess.rating,
        ana.chess.rating,
        reason: 'chess untouched',
      );
      expect(
        (await repo.ladderIn(GameMode.standardBackgammon)).first.id,
        bogdan.id,
      );
      expect(await repo.requestsIn(MatchType.backgammon), isEmpty);
    },
  );

  test('backgammon ladder replays from history', () async {
    final repo = await anaAndBogdanWithBackgammon();
    for (final p in await repo.ladderIn(GameMode.standardBackgammon)) {
      final matches = await repo.results(MatchType.backgammon, playerId: p.id);
      expect(matches.length, p.backgammon.played);
      expect(
        ratingHistory(
          p.id,
          matches.reversed.toList(),
          start: backgammonStartingRating,
        ).last,
        p.backgammon.rating,
      );
    }
  });

  test('backgammon rejects impossible scores and playing yourself', () async {
    final repo = await anaAndBogdan();
    final me = repo.me!;
    final bogdanId = (await repo.ladderIn(GameMode.standardChess))
        .firstWhere((p) => p.id != me.id)
        .id;
    for (final (opponent, mine, theirs) in [
      (me.id, 5, 3),
      (bogdanId, 5, 5),
      (bogdanId, 26, 3),
      (bogdanId, 0, 0),
    ]) {
      await expectLater(
        repo.reportBackgammon(
          opponentId: opponent,
          myScore: mine,
          opponentScore: theirs,
        ),
        throwsA(isA<LadderException>()),
      );
    }
    expect(await repo.requestsIn(MatchType.backgammon), isEmpty);
  });
}
