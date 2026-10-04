import 'package:awake_ladder/app.dart';
import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ladder_fixture.dart';

/// Ana and Bogdan with nothing played. Signed in as Ana.
Future<(DemoLadderRepository, Player ana, Player bogdan)> _fresh() async {
  final repo = DemoLadderRepository();
  await repo.signUp(email: bogdanEmail, password: 'x', displayName: 'Bogdan');
  final bogdan = repo.me!;
  await repo.signOut();
  await repo.signUp(email: anaEmail, password: 'x', displayName: 'Ana');
  return (repo, repo.me!, bogdan);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an unrated chess game is kept but moves nothing', () async {
    final (repo, ana, bogdan) = await _fresh();
    final request = await repo.reportChess(
      opponentId: bogdan.id,
      myColor: PieceColor.white,
      myOutcome: Outcome.win,
      clock: const ClockSetting(TimeControl.sudden5),
      rated: false,
    );
    expect(request.rated, isFalse);

    await repo.signIn(email: bogdanEmail, password: 'x');
    final match = await repo.respondToRequest(request.id, accept: true);

    expect(match!.rated, isFalse);
    expect(match.deltaFor(ana.id), 0);
    expect(match.ratingAfterFor(bogdan.id), 1000);
    expect((await repo.results(MatchType.chess)).single.rated, isFalse);
    for (final p in await repo.ladderIn(GameMode.standardChess)) {
      expect(p.chess.rating, 1000);
      expect(p.chess.played, 0);
      expect(p.chess.wins + p.chess.losses + p.chess.draws, 0);
    }

    // The next rated game is rated as if the friendly never happened.
    final rated = await repo.reportChess(
      opponentId: ana.id,
      myColor: PieceColor.white,
      myOutcome: Outcome.win,
      clock: const ClockSetting(TimeControl.sudden5),
    );
    await repo.signIn(email: anaEmail, password: 'x');
    expect(
      (await repo.respondToRequest(
        rated.id,
        accept: true,
      ))!.deltaFor(bogdan.id),
      20,
    );
  });

  test('an unrated backgammon match leaves rating and experience', () async {
    final (repo, ana, bogdan) = await _fresh();
    final request = await repo.reportBackgammon(
      opponentId: bogdan.id,
      myScore: 7,
      opponentScore: 2,
      rated: false,
    );
    await repo.signIn(email: bogdanEmail, password: 'x');
    final match = await repo.respondToRequest(request.id, accept: true);

    expect(match!.rated, isFalse);
    expect(match.outcomeFor(ana.id), Outcome.win);
    expect(match.deltaFor(ana.id), 0);
    expect(match.deltaFor(bogdan.id), 0);
    for (final p in await repo.ladderIn(GameMode.standardBackgammon)) {
      expect(p.backgammon.rating, 1500);
      expect(p.backgammon.played, 0);
      expect(p.backgammon.experience, 0);
    }
  });

  test('an unrated SWU match moves nothing', () async {
    final (repo, ana, bogdan) = await _fresh();
    final request = await repo.reportSwu(
      opponentId: bogdan.id,
      myGames: 2,
      opponentGames: 1,
      rated: false,
    );
    await repo.signIn(email: bogdanEmail, password: 'x');
    final match = await repo.respondToRequest(request.id, accept: true);

    expect(match!.rated, isFalse);
    expect(match.deltaFor(ana.id), 0);
    expect(match.deltaFor(bogdan.id), 0);
    for (final p in await repo.ladderIn(GameMode.premier)) {
      expect(p.swu.rating, 1000);
      expect(p.swu.played, 0);
    }
  });

  testWidgets('a game recorded as unrated says so all the way through', (
    tester,
  ) async {
    _phone(tester);
    final (repo, ana, _) = await _fresh();
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/record?opponent=demo-1'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('I won'));
    await tester.tap(find.text('White'));
    final clock = find.widgetWithText(ChoiceChip, 'Sudden death 5 min');
    await tester.ensureVisible(clock);
    await tester.pumpAndSettle();
    await tester.tap(clock);
    await tester.pumpAndSettle();
    expect(find.text('1000 to '), findsNWidgets(2), reason: 'rated preview');

    final rated = find.byType(Switch);
    await tester.ensureVisible(rated);
    await tester.pumpAndSettle();
    await tester.tap(rated);
    await tester.pumpAndSettle();
    expect(find.text('Unrated: no rating changes.'), findsOneWidget);
    expect(find.text('1000 to '), findsNothing);

    final send = find.widgetWithText(FilledButton, 'Send for confirmation');
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(find.textContaining('goes in the history'), findsOneWidget);
    expect(find.textContaining('· Unrated'), findsOneWidget);

    expect(repo.me!.chess.rating, 1000);
    expect(ana.chess.rating, 1000);
  });

  testWidgets('confirming an unrated game leaves ratings and lists it', (
    tester,
  ) async {
    _phone(tester);
    final (repo, ana, _) = await _fresh();
    await repo.signIn(email: bogdanEmail, password: 'x');
    await repo.reportChess(
      opponentId: ana.id,
      myColor: PieceColor.black,
      myOutcome: Outcome.loss,
      clock: const ClockSetting(TimeControl.sudden5),
      rated: false,
    );
    await repo.signIn(email: anaEmail, password: 'x');
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('· Unrated'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(find.textContaining('confirmed as unrated'), findsOneWidget);
    expect(repo.me!.chess.rating, 1000);

    await tester.tap(find.text('History').last);
    await tester.pumpAndSettle();
    expect(find.text('Unrated'), findsOneWidget);
  });
}
