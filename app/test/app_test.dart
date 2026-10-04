import 'package:awake_ladder/app.dart';
import 'package:awake_ladder/domain/backgammon.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:awake_ladder/ui/ladder/baize_ladder.dart';
import 'package:awake_ladder/ui/ladder/pawns_ladder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ladder_fixture.dart';

void _phone(WidgetTester tester, {double width = 360}) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The page's ListView (text fields have scrollables of their own).
final _list = find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

Finder _awaitingBadge(String count) =>
    find.descendant(of: find.byType(Badge), matching: find.text(count));

void main() {
  testWidgets('signing in lands on the ladder', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await repo.signOut();
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('Chess and backgammon'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      anaEmail,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'secret',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('The ladder'), findsOneWidget);
    expect(find.textContaining('You\'re '), findsOneWidget);
  });

  testWidgets('a recorded game waits for the opponent to confirm', (
    tester,
  ) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    final before = repo.me!.rating;
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/record?opponent=demo-2'),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Pick an opponent and a result'),
      findsOneWidget,
    );
    await tester.tap(find.text('I won'));
    final clock = find.byType(DropdownMenu<TimeControl>);
    await tester.ensureVisible(clock);
    await tester.pumpAndSettle();
    await tester.tap(clock);
    await tester.pumpAndSettle();
    final fischer = find.text('Fischer custom').last;
    await tester.ensureVisible(fischer);
    await tester.pumpAndSettle();
    await tester.tap(fischer);
    await tester.pumpAndSettle();
    final send = find.widgetWithText(FilledButton, 'Send for confirmation');
    await tester.enterText(find.widgetWithText(TextField, 'Minutes each'), '7');
    await tester.pump();
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Increment (s)'),
      '4',
    );
    await tester.pumpAndSettle();
    expect(find.text('Bogdan'), findsWidgets);

    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(repo.me!.rating, before);
    expect(find.textContaining('Sent to Bogdan'), findsOneWidget);
    expect(find.text('The ladder'), findsOneWidget);
    expect(find.text('Waiting for Bogdan to confirm'), findsOneWidget);
    expect(find.textContaining('Fischer 7 min + 4 s'), findsOneWidget);
  });

  testWidgets('confirming a game reported against you rates it', (
    tester,
  ) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    final before = repo.me!.rating;
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('Bogdan says you lost'), findsOneWidget);
    expect(_awaitingBadge('1'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(repo.me!.rating, lessThan(before));
    expect(
      find.textContaining('Game confirmed. You\'re now ${repo.me!.rating}'),
      findsOneWidget,
    );
    expect(find.text('Bogdan says you lost'), findsNothing);
    expect(_awaitingBadge('1'), findsNothing);
  });

  testWidgets('wide screens navigate from the header', (tester) async {
    _phone(tester, width: 1024);
    final repo = await anaAndBogdan();
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('Awake Ladder'), findsOneWidget);
    expect(_awaitingBadge('1'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Record game'));
    await tester.pumpAndSettle();
    expect(find.text('Record a game'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(
      find.text('Every game played at Awake, newest first.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('You'));
    await tester.pumpAndSettle();
    expect(find.text('Rating over time'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backgammon'));
    await tester.pumpAndSettle();
    expect(find.text('YOUR LADDERS'), findsNothing);
    expect(find.text('Backgammon rating'), findsOneWidget);
  });

  testWidgets('every screen renders at 360px', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    for (final tab in ['Record', 'History', 'You']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Save name'), findsOneWidget);

    // Back to the ladder, then open another player's profile.
    await tester.tap(find.text('Ladder').last);
    await tester.pumpAndSettle();
    final bogdan = find
        .descendant(
          of: find.byType(PawnsLadder),
          matching: find.textContaining('Bogdan'),
        )
        .first;
    await tester.ensureVisible(bogdan);
    await tester.pumpAndSettle();
    await tester.tap(bogdan);
    await tester.pumpAndSettle();
    expect(find.text('Rating over time'), findsOneWidget);
    expect(find.textContaining('Record a game with'), findsOneWidget);
  });

  testWidgets('saving a display name renames you on your profile', (
    tester,
  ) async {
    _phone(tester, width: 400);
    final repo = await anaAndBogdan();
    await tester.pumpWidget(AwakeApp(repository: repo, initialLocation: '/me'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    final field = find.byType(TextFormField);
    final save = find.widgetWithText(FilledButton, 'Save name');
    Rect rectOf(Finder f) => tester.getRect(f);
    expect(rectOf(save).top, rectOf(field).top);
    expect(rectOf(save).bottom, rectOf(field).bottom);

    await tester.enterText(field, 'A');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Use at least 2 characters'), findsOneWidget);
    expect(rectOf(save).top, rectOf(field).top);

    await tester.enterText(field, 'Ana Banana');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repo.me!.displayName, 'Ana Banana');
    expect(find.text('Name saved.'), findsOneWidget);

    await tester.tap(find.text('You').last);
    await tester.pumpAndSettle();
    expect(find.text('Ana Banana'), findsOneWidget);
  });

  testWidgets('signing out returns to sign-in', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/settings'),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sign out'),
      200,
      scrollable: _list,
    );
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('each game has its own ladder, picked from its card', (
    tester,
  ) async {
    _phone(tester);
    final repo = await anaAndBogdanWithBackgammon();
    final ana = repo.me!;
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('The ladder'), findsOneWidget);
    // Pending chess game on the Ladder tab, pending match on the picker.
    expect(_awaitingBadge('1'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Switch game'));
    await tester.pumpAndSettle();
    expect(find.text('YOUR LADDERS'), findsOneWidget);
    expect(find.text('1 to confirm'), findsNWidgets(2));
    expect(
      find.text('${ana.backgammon.rating} · 1st of 2', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text('Backgammon'));
    await tester.pumpAndSettle();
    expect(find.text('YOUR LADDERS'), findsNothing);
    expect(find.text('The race'), findsOneWidget);
    expect(find.byType(PawnsLadder), findsNothing);
    final race = find.byType(BaizeLadder);
    expect(
      find.descendant(
        of: race,
        matching: find.text('${ana.backgammon.rating}'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: race, matching: find.text('${ana.rating}')),
      findsNothing,
    );
    expect(find.text('Bogdan says you lost 1-3'), findsOneWidget);

    // The picker keeps the tab.
    await tester.tap(find.text('History').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chess'));
    await tester.pumpAndSettle();
    expect(
      find.text('Every game played at Awake, newest first.'),
      findsOneWidget,
    );
  });

  testWidgets('a recorded backgammon match waits for the opponent', (
    tester,
  ) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await tester.pumpWidget(
      AwakeApp(
        repository: repo,
        initialLocation: '/backgammon/record?opponent=demo-2',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Record a match'), findsOneWidget);
    final send = find.widgetWithText(FilledButton, 'Send for confirmation');
    final raiseMine = find.byTooltip('Raise your score');
    final raiseTheirs = find.byTooltip('Raise Bogdan\'s score');
    await tester.ensureVisible(raiseTheirs);
    for (var i = 0; i < 5; i++) {
      await tester.tap(raiseMine);
      await tester.pump();
    }
    await tester.tap(raiseTheirs);
    await tester.pumpAndSettle();
    expect(find.text('1500 to '), findsNWidgets(2));
    expect(find.text('+22'), findsOneWidget);

    // Nobody can win a match to 3 with 5 points: scores clamp to the length.
    await tester.tap(find.bySemanticsLabel('Match to 3'));
    await tester.pumpAndSettle();
    expect(find.text('+17'), findsOneWidget);

    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(find.textContaining('Sent to Bogdan'), findsOneWidget);
    expect(find.text('The race'), findsOneWidget);
    expect(find.text('Waiting for Bogdan to confirm'), findsOneWidget);
    expect(find.text('Match to 3, you won 3-1'), findsOneWidget);
    expect(repo.me!.backgammon.rating, backgammonStartingRating);
  });

  testWidgets('confirming a backgammon match rates it', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdanWithBackgammon();
    final before = repo.me!.backgammon.rating;
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/backgammon'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(repo.me!.backgammon.rating, lessThan(before));
    expect(
      find.textContaining(
        'Match confirmed. You\'re now ${repo.me!.backgammon.rating}',
      ),
      findsOneWidget,
    );
    expect(find.text('Bogdan says you lost 1-3'), findsNothing);
  });

  testWidgets('every backgammon screen renders at 360px', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdanWithBackgammon();
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/backgammon'),
    );
    await tester.pumpAndSettle();

    for (final tab in ['Record', 'History', 'You']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    expect(find.text('Backgammon rating'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Won against Bogdan'),
      200,
      scrollable: _list,
    );
    await tester.scrollUntilVisible(
      find.byTooltip('Settings'),
      -200,
      scrollable: _list,
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Save name'), findsOneWidget);
    expect(find.text('Backgammon'), findsOneWidget);

    await tester.tap(find.text('Ladder').last);
    await tester.pumpAndSettle();
    final bogdan = find
        .descendant(
          of: find.byType(BaizeLadder),
          matching: find.textContaining('Bogdan'),
        )
        .first;
    await tester.ensureVisible(bogdan);
    await tester.pumpAndSettle();
    await tester.tap(bogdan);
    await tester.pumpAndSettle();
    expect(find.text('Record a match with Bogdan'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Lost to Ana'),
      200,
      scrollable: _list,
    );
  });
}
