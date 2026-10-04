import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/domain/backgammon.dart';
import 'package:awake_ladder/data/ladder_repository.dart';
import 'package:awake_ladder/domain/elo.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ladder_fixture.dart';

void main() {
  test('a new ladder starts empty', () async {
    expect(await DemoLadderRepository().ladder(), isEmpty);
  });

  test('ladder replays from history', () async {
    final repo = await anaAndBogdan();
    final players = await repo.ladder();

    for (final p in players) {
      final games = await repo.matches(playerId: p.id, limit: 1000);
      expect(games.length, p.gamesPlayed);
      expect(p.wins + p.losses + p.draws, p.gamesPlayed);
      final history = ratingHistory(p.id, games.reversed.toList());
      expect(history.first, startingRating);
      expect(history.last, p.rating);
    }
  });

  test('deleting an account keeps confirmed results under its name', () async {
    final repo = await anaAndBogdan();
    final ana = repo.me!;
    await repo.deleteAccount();
    expect(repo.isSignedIn, isFalse);

    // Ana is off the ladder and her login is gone, but Bogdan keeps the
    // rating her game gave him and still sees the game against "Ana".
    expect((await repo.ladder()).map((p) => p.displayName), ['Bogdan']);
    await repo.signIn(email: bogdanEmail, password: 'x');
    final bogdan = repo.me!;
    final games = await repo.matches(playerId: bogdan.id);
    expect(games, hasLength(1));
    expect(games.single.opponentName(bogdan.id), 'Ana');
    expect(games.single.opponentId(bogdan.id), ana.id);
    expect(bogdan.rating, lessThan(startingRating));
    // What was waiting on her answer went with her.
    expect(await repo.matchRequests(), isEmpty);
    await expectLater(repo.player(ana.id), throwsA(isA<LadderException>()));
  });

  test('deleting an account needs a signed-in member', () async {
    await expectLater(
      DemoLadderRepository().deleteAccount(),
      throwsA(isA<LadderException>()),
    );
  });

  test('ladder is sorted by rating, then games, then name', () async {
    final players = await (await anaAndBogdan()).ladder();
    for (var i = 1; i < players.length; i++) {
      expect(compareLadder(players[i - 1], players[i]), lessThanOrEqualTo(0));
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
    expect(ana.rating, 1000);

    final request = await repo.requestMatch(
      opponentId: bo.id,
      myColor: PieceColor.black,
      myOutcome: Outcome.win,
      clock: const ClockSetting(TimeControl.fischer5plus3),
    );
    expect(request.result, MatchResult.black);
    expect(request.awaits(ana.id), isFalse);
    expect(repo.me!.rating, 1000);
    expect(await repo.matches(), isEmpty);
    await expectLater(
      repo.respondToMatchRequest(request.id, accept: true),
      throwsA(isA<LadderException>()),
    );

    await repo.signIn(email: 'bo@example.com', password: 'password');
    final pending = await repo.matchRequests();
    expect(pending.single.awaits(bo.id), isTrue);
    final revision = repo.revision;
    final match = await repo.respondToMatchRequest(request.id, accept: true);

    expect(match!.deltaFor(ana.id), 20);
    expect(match.clock!.preset, TimeControl.fischer5plus3);
    expect(repo.me!.rating, 980);
    expect((await repo.player(ana.id)).rating, 1020);
    expect(await repo.matchRequests(), isEmpty);
    expect(repo.revision, greaterThan(revision));
  });

  test('declined and withdrawn games are never rated', () async {
    final repo = await anaAndBogdan();
    final ana = repo.me!;
    final incoming = (await repo.matchRequests()).single;
    expect(incoming.awaits(ana.id), isTrue);
    expect(
      await repo.respondToMatchRequest(incoming.id, accept: false),
      isNull,
    );

    final mine = await repo.requestMatch(
      opponentId: incoming.opponentId(ana.id),
      myColor: PieceColor.white,
      myOutcome: Outcome.draw,
      clock: const ClockSetting(TimeControl.sudden5),
    );
    expect(await repo.respondToMatchRequest(mine.id, accept: false), isNull);

    expect(await repo.matchRequests(), isEmpty);
    expect(repo.me!.rating, ana.rating);
    expect(repo.me!.gamesPlayed, ana.gamesPlayed);
  });

  test(
    'a declined game stays for the reporter until they dismiss it',
    () async {
      final repo = await anaAndBogdan();
      final ana = repo.me!;
      final request = (await repo.matchRequests()).single;
      final bogdanId = request.requestedBy;
      await repo.respondToMatchRequest(request.id, accept: false);

      // The decliner has nothing left to answer and can't answer it again.
      expect(await repo.matchRequests(), isEmpty);
      await expectLater(
        repo.respondToMatchRequest(request.id, accept: false),
        throwsA(isA<LadderException>()),
      );
      await expectLater(
        repo.dismissMatchRequest(request.id),
        throwsA(isA<LadderException>()),
      );

      await repo.signIn(email: bogdanEmail, password: 'x');
      final declined = (await repo.matchRequests()).single;
      expect(declined.status, RequestStatus.declined);
      expect(declined.respondedAt, isNotNull);
      expect(declined.declinedFor(bogdanId), isTrue);
      expect(declined.awaits(bogdanId), isFalse);
      expect(declined.awaits(ana.id), isFalse);
      await expectLater(
        repo.respondToMatchRequest(request.id, accept: true),
        throwsA(isA<LadderException>()),
        reason: 'a declined game can no longer be confirmed',
      );

      await repo.dismissMatchRequest(request.id);
      expect(await repo.matchRequests(), isEmpty);
      expect((await repo.player(ana.id)).rating, ana.rating);
    },
  );

  test(
    'a declined backgammon or SWU match is dismissed the same way',
    () async {
      final repo = await anaAndBogdanWithSwu();
      final bgRequest = (await repo.backgammonMatchRequests()).single;
      final swuRequest = (await repo.swuMatchRequests()).single;
      await repo.respondToBackgammonMatchRequest(bgRequest.id, accept: false);
      await repo.respondToSwuMatchRequest(swuRequest.id, accept: false);
      expect(await repo.backgammonMatchRequests(), isEmpty);
      expect(await repo.swuMatchRequests(), isEmpty);

      await repo.signIn(email: bogdanEmail, password: 'x');
      final bogdanId = repo.me!.id;
      final bg = (await repo.backgammonMatchRequests()).single;
      final swu = (await repo.swuMatchRequests()).single;
      expect(bg.declinedFor(bogdanId) && !bg.awaits(bogdanId), isTrue);
      expect(swu.declinedFor(bogdanId) && !swu.awaits(bogdanId), isTrue);

      await repo.dismissBackgammonMatchRequest(bg.id);
      await repo.dismissSwuMatchRequest(swu.id);
      expect(await repo.backgammonMatchRequests(), isEmpty);
      expect(await repo.swuMatchRequests(), isEmpty);
      await expectLater(
        repo.dismissSwuMatchRequest(swu.id),
        throwsA(isA<LadderException>()),
      );
    },
  );

  test('a pending game can only be withdrawn, not dismissed', () async {
    final repo = await anaAndBogdan();
    final ana = repo.me!;
    final mine = await repo.requestMatch(
      opponentId: (await repo.matchRequests()).single.requestedBy,
      myColor: PieceColor.white,
      myOutcome: Outcome.win,
      clock: const ClockSetting(TimeControl.sudden5),
    );
    await expectLater(
      repo.dismissMatchRequest(mine.id),
      throwsA(isA<LadderException>()),
    );
    await repo.respondToMatchRequest(mine.id, accept: false);
    expect(
      (await repo.matchRequests()).where((r) => r.requestedBy == ana.id),
      isEmpty,
      reason: 'withdrawing deletes outright',
    );
  });

  test('custom presets need the time the players set', () async {
    final repo = await anaAndBogdan();
    final opponentId = (await repo.ladder())
        .firstWhere((p) => p.id != repo.me!.id)
        .id;
    Future<MatchRequest> request(ClockSetting clock) => repo.requestMatch(
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
    expect(sent.clock.label, 'Fischer 7 min + 4 s');
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
      repo.requestMatch(
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
      final bogdan = (await repo.ladder()).firstWhere((p) => p.id != ana.id);
      expect(ana.backgammon.rating, backgammonStartingRating);

      final request = await repo.requestBackgammonMatch(
        opponentId: bogdan.id,
        matchLength: 5,
        myScore: 3,
        opponentScore: 5,
      );
      expect(request.winnerId, bogdan.id);
      expect(request.loserScore, 3);
      expect(await repo.backgammonMatches(), isEmpty);
      await expectLater(
        repo.respondToBackgammonMatchRequest(request.id, accept: true),
        throwsA(isA<LadderException>()),
      );

      await repo.signIn(email: bogdanEmail, password: 'x');
      final match = await repo.respondToBackgammonMatchRequest(
        request.id,
        accept: true,
      );
      expect(match!.deltaFor(bogdan.id), 22);
      expect(match.deltaFor(ana.id), -22);

      final players = {for (final p in await repo.backgammonLadder()) p.id: p};
      expect(players[bogdan.id]!.backgammon.rating, 1522);
      expect(players[bogdan.id]!.backgammon.experience, 5);
      expect(players[ana.id]!.backgammon.rating, 1478);
      expect(players[ana.id]!.backgammon.losses, 1);
      expect(players[ana.id]!.rating, ana.rating, reason: 'chess untouched');
      expect((await repo.backgammonLadder()).first.id, bogdan.id);
      expect(await repo.backgammonMatchRequests(), isEmpty);
    },
  );

  test('backgammon ladder replays from history', () async {
    final repo = await anaAndBogdanWithBackgammon();
    for (final p in await repo.backgammonLadder()) {
      final matches = await repo.backgammonMatches(playerId: p.id);
      expect(matches.length, p.backgammon.matchesPlayed);
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
    final bogdanId = (await repo.ladder()).firstWhere((p) => p.id != me.id).id;
    for (final (opponent, length, mine, theirs) in [
      (me.id, 5, 5, 3),
      (bogdanId, 5, 5, 5),
      (bogdanId, 5, 4, 3),
      (bogdanId, 0, 0, 0),
    ]) {
      await expectLater(
        repo.requestBackgammonMatch(
          opponentId: opponent,
          matchLength: length,
          myScore: mine,
          opponentScore: theirs,
        ),
        throwsA(isA<LadderException>()),
      );
    }
    expect(await repo.backgammonMatchRequests(), isEmpty);
  });
}
