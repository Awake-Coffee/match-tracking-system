import 'package:awake_ladder/app.dart';
import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/data/ladder_repository.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:awake_ladder/ui/ladder/route_ladder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ladder_fixture.dart';

/// Ana, Bea, Cal and Dan by name, signed in as Ana.
Future<(DemoLadderRepository, Map<String, String>)> _fourMembers() async {
  final repo = DemoLadderRepository();
  final ids = <String, String>{};
  for (final name in ['Ana', 'Bea', 'Cal', 'Dan']) {
    await repo.signUp(
      email: '${name.toLowerCase()}@example.com',
      password: 'x',
      displayName: name,
    );
    ids[name] = repo.me!.id;
    await repo.signOut();
  }
  await _as(repo, 'Ana');
  return (repo, ids);
}

Future<void> _as(DemoLadderRepository repo, String name) =>
    repo.signIn(email: '${name.toLowerCase()}@example.com', password: 'x');

/// [players] as (name, side, score) seats.
List<SeatReport> _seats(
  Map<String, String> ids,
  List<(String, int, num)> players,
) => [
  for (final (name, side, score) in players)
    (playerId: ids[name]!, side: side, score: score),
];

void main() {
  test('a chess960 game is rated on its own ladder', () async {
    final (repo, ids) = await _fourMembers();
    final request = await repo.reportChess(
      opponentId: ids['Bea']!,
      myColor: PieceColor.white,
      myOutcome: Outcome.win,
      clock: const ClockSetting(TimeControl.fischer5plus3),
      mode: GameMode.chess960,
    );
    await _as(repo, 'Bea');
    await repo.respondToRequest(request.id, accept: true);

    final ana = await repo.player(ids['Ana']!);
    expect(ana.standingIn(GameMode.chess960).rating, 1020);
    expect(ana.chess.played, 0, reason: 'standard chess untouched');
    expect(await repo.results(MatchType.chess, mode: GameMode.chess960), [
      isA<GameResult>(),
    ]);
    expect(
      await repo.results(MatchType.chess, mode: GameMode.standardChess),
      isEmpty,
    );
  });

  // Same flow and numbers as supabase/tests/game_modes_test.sql.
  test('twin suns counts once everyone confirms, by place', () async {
    final (repo, ids) = await _fourMembers();
    final request = await repo.reportResult(
      ResultReport(
        mode: GameMode.twinSuns,
        seats: _seats(ids, [
          ('Ana', 1, 3),
          ('Bea', 2, 2),
          ('Cal', 3, 0),
          ('Dan', 4, 0),
        ]),
      ),
    );
    await expectLater(
      repo.respondToRequest(request.id, accept: true),
      throwsA(isA<LadderException>()),
      reason: 'the reporter can\'t confirm their own result',
    );

    await _as(repo, 'Bea');
    expect(await repo.respondToRequest(request.id, accept: true), isNull);
    final waiting = (await repo.requests()).single;
    expect([for (final s in waiting.waitingOn) s.name], ['Cal', 'Dan']);
    expect(waiting.awaits(ids['Bea']!), isFalse);
    expect((await repo.player(ids['Ana']!)).standings, isEmpty);

    await _as(repo, 'Cal');
    expect(await repo.respondToRequest(request.id, accept: true), isNull);
    await _as(repo, 'Dan');
    final rated = await repo.respondToRequest(request.id, accept: true);

    expect(
      {for (final s in rated!.seats) s.name: s.ratingDelta},
      {'Ana': 20, 'Bea': 7, 'Cal': -13, 'Dan': -13},
    );
    expect(
      [for (final s in rated.seats) rated.placeOf(s.playerId)],
      [1, 2, 3, 3],
    );
    final ladder = await repo.ladderIn(GameMode.twinSuns);
    expect(
      [for (final p in ladder) p.displayName],
      ['Ana', 'Bea', 'Cal', 'Dan'],
    );
    expect(
      [for (final p in ladder) p.standingIn(GameMode.twinSuns).record],
      ['1-0-0', '0-1-0', '0-1-0', '0-1-0'],
    );
    expect(ladder.first.swu.played, 0, reason: 'premier untouched');
    expect(await repo.requests(), isEmpty);
  });

  test(
    'a bughouse teammate can decline, and the reporter learns who',
    () async {
      final (repo, ids) = await _fourMembers();
      final request = await repo.reportResult(
        ResultReport(
          mode: GameMode.bughouse,
          seats: _seats(ids, [
            ('Ana', 1, 1),
            ('Bea', 1, 1),
            ('Cal', 2, 0),
            ('Dan', 2, 0),
          ]),
          clock: const ClockSetting(TimeControl.sudden5),
        ),
      );
      await _as(repo, 'Cal');
      await repo.respondToRequest(request.id, accept: true);
      await _as(repo, 'Bea');
      await repo.respondToRequest(request.id, accept: false);

      expect(await repo.requests(), isEmpty, reason: 'gone for the decliner');
      await _as(repo, 'Cal');
      expect(await repo.requests(), isEmpty, reason: 'and for the others');
      await _as(repo, 'Ana');
      final declined = (await repo.requests()).single;
      expect(declined.declinedFor(ids['Ana']!), isTrue);
      expect(declined.declinedBy, ids['Bea']);
      expect(await repo.results(MatchType.chess), isEmpty);
    },
  );

  test('a chouette box plays the whole team', () async {
    final (repo, ids) = await _fourMembers();
    final request = await repo.reportResult(
      ResultReport(
        mode: GameMode.chouette,
        seats: _seats(ids, [
          ('Dan', 1, 3),
          ('Ana', 2, 5),
          ('Bea', 2, 5),
          ('Cal', 2, 5),
        ]),
      ),
    );
    for (final name in ['Bea', 'Cal', 'Dan']) {
      await _as(repo, name);
      await repo.respondToRequest(request.id, accept: true);
    }
    final ladder = await repo.ladderIn(GameMode.chouette);
    expect(
      {for (final p in ladder) p.displayName: p.standingIn(GameMode.chouette)}
          .map((name, s) => MapEntry(name, (s.rating, s.experience))),
      {'Ana': (1522, 5), 'Bea': (1522, 5), 'Cal': (1522, 5), 'Dan': (1478, 5)},
    );
  });

  test('results that don\'t fit their mode are refused', () async {
    final (repo, ids) = await _fourMembers();
    for (final (mode, players) in [
      // Two players can't both have outlasted only one.
      (GameMode.twinSuns, [('Ana', 1, 2), ('Bea', 2, 1), ('Cal', 3, 1)]),
      (GameMode.twinSuns, [('Bea', 1, 1), ('Cal', 2, 0)]),
      (GameMode.bughouse, [('Ana', 1, 1), ('Bea', 2, 0)]),
      (
        GameMode.bughouse,
        [('Ana', 1, 1), ('Bea', 1, 0), ('Cal', 2, 0), ('Dan', 2, 0)],
      ),
      (GameMode.chouette, [('Ana', 1, 5), ('Bea', 2, 3)]),
      (GameMode.premier, [('Ana', 1, 2), ('Bea', 2, 0), ('Cal', 2, 0)]),
    ]) {
      await expectLater(
        repo.reportResult(
          ResultReport(
            mode: mode,
            seats: _seats(ids, players),
            clock: mode.type == MatchType.chess
                ? const ClockSetting(TimeControl.sudden5)
                : null,
          ),
        ),
        throwsA(isA<LadderException>()),
        reason: '${mode.label} $players',
      );
    }
    expect(await repo.requests(), isEmpty);
  });

  group('screens', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    final list = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;

    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(finder, 200, scrollable: list);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    /// Opens the app at [location] as [name], as after signing in on a
    /// device of their own.
    Future<void> openAs(
      WidgetTester tester,
      DemoLadderRepository repo,
      String name,
      String location,
    ) async {
      await _as(repo, name);
      await tester.pumpWidget(
        AwakeApp(
          key: ValueKey(name),
          repository: repo,
          initialLocation: location,
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Picks [name] from the "Add a player" menu.
    Future<void> addPlayer(WidgetTester tester, String name) async {
      await tapVisible(tester, find.byType(DropdownMenu<String>).last);
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    testWidgets('twin suns is recorded in finishing order and confirmed by '
        'everyone', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (repo, _) = await _fourMembers();
      await tester.pumpWidget(
        AwakeApp(
          repository: repo,
          initialLocation: '/swu/record?mode=twin_suns',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('2–4 player free-for-all, two leaders each'),
        findsOneWidget,
      );
      await addPlayer(tester, 'Bea');
      await addPlayer(tester, 'Cal');
      expect(find.text('Finishing order · drag to reorder'), findsOneWidget);
      expect(find.text('Winner'), findsOneWidget);

      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Send for confirmation'),
      );
      expect(find.textContaining('Sent to Bea & Cal'), findsOneWidget);
      expect(find.text('Waiting for Bea & Cal to confirm'), findsOneWidget);
      expect(
        find.text('Twin Suns · 3 players, you came 1st of 3'),
        findsOneWidget,
      );
      expect(find.text('reported'), findsOneWidget);
      expect(find.text('waiting'), findsNWidgets(2));

      await openAs(tester, repo, 'Bea', '/swu');
      expect(find.text('Ana says you came 2nd of 3'), findsOneWidget);
      expect(find.text('waiting on you'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Confirm'));
      expect(find.text('Confirmed. Waiting for Cal.'), findsOneWidget);
      expect(find.text('Waiting for Cal to confirm'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Withdraw'), findsNothing);

      await openAs(tester, repo, 'Cal', '/swu');
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Confirm'));
      expect(
        find.textContaining('Match confirmed. You\'re now'),
        findsOneWidget,
      );

      await tapVisible(tester, find.text('Twin Suns'));
      expect(find.byType(RouteLadder), findsOneWidget);
      expect(find.text('Cal (you)'), findsOneWidget);
    });

    testWidgets('the mode menu records a chess960 game on its own ladder', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (repo, ids) = await _fourMembers();
      await tester.pumpWidget(
        AwakeApp(
          repository: repo,
          initialLocation: '/record?opponent=${ids['Bea']}',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownMenu<GameMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chess960').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Back ranks shuffled, mirrored for both sides'),
        findsOneWidget,
      );
      expect(
        find.text('Rated on its own ladder · you start at 1000'),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('I won'));
      await tapVisible(tester, find.text('White'));
      await tapVisible(
        tester,
        find.widgetWithText(ChoiceChip, 'Fischer 5 min + 3 s'),
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Send for confirmation'),
      );
      expect(
        find.text('Chess960 · You had white, you won · Fischer 5 min + 3 s'),
        findsOneWidget,
      );

      await openAs(tester, repo, 'Bea', '/');
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Confirm'));
      // Bea has played Chess960 now, so it leads her ladders.
      expect(
        tester.getTopLeft(find.text('Chess960')).dy,
        lessThan(tester.getTopLeft(find.text('Standard')).dy),
      );
      expect(find.text('2nd'), findsOneWidget);
    });

    testWidgets('bughouse and chouette forms fit a phone and send', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (repo, _) = await _fourMembers();

      await tester.pumpWidget(
        AwakeApp(repository: repo, initialLocation: '/record?mode=bughouse'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your partner'), findsOneWidget);
      expect(find.text('Time control (both clocks)'), findsOneWidget);
      expect(
        find.text(
          'Pick your partner, two opponents, a result and a time control',
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(
        AwakeApp(
          key: const ValueKey('chouette'),
          repository: repo,
          initialLocation: '/backgammon/record?mode=chouette',
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('In the box'));
      await addPlayer(tester, 'Bea');
      await addPlayer(tester, 'Cal');
      await tapVisible(tester, find.text('I won'));
      await tapVisible(tester, find.widgetWithText(ChoiceChip, '2'));
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Send for confirmation'),
      );
      expect(find.textContaining('Sent to Bea & Cal'), findsOneWidget);
      final sent = (await repo.requests()).single;
      expect(sent.mode, GameMode.chouette);
      expect(
        [for (final s in sent.seats) (s.name, s.side, s.score)],
        [('Ana', 1, 5), ('Bea', 2, 2), ('Cal', 2, 2)],
      );
    });
  });
}
