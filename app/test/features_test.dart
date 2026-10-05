import 'package:awake_ladder/app.dart';
import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:awake_ladder/features.dart';
import 'package:awake_ladder/ui/ladder/baize_ladder.dart';
import 'package:awake_ladder/ui/ladder/counter_ladder.dart';
import 'package:awake_ladder/ui/ladder/route_ladder.dart';
import 'package:awake_ladder/ui/widgets/match_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ladder_fixture.dart';

/// The app as released: features still being finished are off.
const _released = Features();

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _open(
  WidgetTester tester,
  DemoLadderRepository repo, {
  String at = '/',
}) async {
  await tester.pumpWidget(
    // A new app each time: the router reads initialLocation only once.
    AwakeApp(
      key: UniqueKey(),
      repository: repo,
      initialLocation: at,
      features: _released,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('with game modes hidden', () {
    testWidgets('the Ladder tab is the standard ladder, called Ladder', (
      tester,
    ) async {
      _phone(tester);
      await _open(tester, await anaAndBogdan());

      expect(find.byType(CounterLadder), findsOneWidget);
      expect(find.text('LADDER'), findsOneWidget);
      expect(find.text('STANDARD'), findsNothing);
      expect(find.text('LADDERS'), findsNothing);
      expect(find.byTooltip('All ladders'), findsNothing);

      // Back from another tab, it is the same ladder.
      await tester.tap(find.text('History').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ladder').last);
      await tester.pumpAndSettle();
      expect(find.text('LADDER'), findsOneWidget);
    });

    testWidgets('backgammon and SWU open straight onto their ladders', (
      tester,
    ) async {
      _phone(tester);
      final repo = await anaAndBogdanWithSwu();
      await _open(tester, repo, at: '/backgammon');
      expect(find.byType(BaizeLadder), findsOneWidget);
      expect(find.text('Ladders'), findsNothing);
      expect(find.byTooltip('All ladders'), findsNothing);

      await _open(tester, repo, at: '/swu');
      expect(find.byType(RouteLadder), findsOneWidget);
      expect(find.text('Ladders'), findsNothing);
    });

    testWidgets('recording and profiles offer no mode', (tester) async {
      _phone(tester);
      final repo = await anaAndBogdan();

      await _open(tester, repo, at: '/record');
      expect(find.byType(DropdownMenu<GameMode>), findsNothing);
      expect(find.text('Mode'), findsNothing);
      expect(find.text('I won'), findsOneWidget);

      await _open(tester, repo, at: '/me');
      expect(find.byType(DropdownMenu<GameMode>), findsNothing);
      expect(find.text('Chess rating'), findsOneWidget);
    });

    testWidgets('standard results go without the mode\'s name', (tester) async {
      _phone(tester);
      final repo = await anaAndBogdan();
      await _open(tester, repo);

      // Bogdan's report waiting for Ana.
      expect(find.text('Bogdan says you lost'), findsOneWidget);
      expect(find.textContaining('Standard'), findsNothing);

      await tester.tap(switchGame);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(' in Standard', findRichText: true),
        findsNothing,
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await _open(tester, repo, at: '/history');
      expect(find.text('Every game played at Awake, newest first.'), findsOne);
      expect(find.byType(ModeChip), findsNothing);
    });

    testWidgets('a result in a hidden mode still says which', (tester) async {
      _phone(tester);
      final repo = await anaAndBogdan();
      final bogdanId = (await repo.members())
          .firstWhere((p) => p.id != repo.me!.id)
          .id;
      final request = await repo.reportChess(
        opponentId: bogdanId,
        myColor: PieceColor.white,
        myOutcome: Outcome.win,
        clock: const ClockSetting(TimeControl.fischer5plus3),
        mode: GameMode.chess960,
      );
      await repo.signIn(email: bogdanEmail, password: 'x');
      await repo.respondToRequest(request.id, accept: true);
      await repo.signIn(email: anaEmail, password: 'x');

      await _open(tester, repo, at: '/history');
      // Only the Chess960 game is tagged; the standard one is not.
      expect(find.byType(ModeChip), findsOneWidget);
      expect(find.text('CHESS960'), findsOneWidget);
    });
  });

  test('a build shows game modes only when told to', () {
    expect(const Features().gameModes, isFalse);
    expect(
      Features.fromEnvironment.gameModes,
      const bool.fromEnvironment('GAME_MODES'),
    );
  });
}
