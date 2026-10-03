import 'package:awake_ladder/app.dart';
import 'package:awake_ladder/domain/models.dart';
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

void main() {
  testWidgets('signing in lands on the ladder', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await repo.signOut();
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('Chess ladder'), findsOneWidget);
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
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(repo.me!.rating, lessThan(before));
    expect(
      find.textContaining('Game confirmed. You\'re now ${repo.me!.rating}'),
      findsOneWidget,
    );
    expect(find.text('Bogdan says you lost'), findsNothing);
  });

  testWidgets('every screen renders at 360px', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    for (final tab in ['Record game', 'History', 'You']) {
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
}
