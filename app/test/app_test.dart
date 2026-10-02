import 'package:awake_ladder/app.dart';
import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/design/design_spec.dart';
import 'package:awake_ladder/design/designs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DemoLadderRepository> _signedIn() async {
  final repo = DemoLadderRepository(now: DateTime(2026, 10, 2, 9));
  await repo.signIn(email: 'ana@awake.coffee', password: 'x');
  return repo;
}

void _phone(WidgetTester tester, {double width = 360}) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The page's ListView (text fields have scrollables of their own).
final _list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;

void main() {
  setUpAll(() => useGoogleFonts = false);

  testWidgets('signing in lands on the ladder', (tester) async {
    _phone(tester);
    await tester.pumpWidget(AwakeApp(repository: DemoLadderRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Chess ladder'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'ana@awake.coffee');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Today\'s ladder'), findsOneWidget);
    expect(find.textContaining('You\'re '), findsOneWidget);
  });

  testWidgets('recording a game updates the rating and returns to the ladder', (tester) async {
    _phone(tester);
    final repo = await _signedIn();
    final before = repo.me!.rating;
    await tester.pumpWidget(AwakeApp(repository: repo, initialLocation: '/record?opponent=demo-2'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pick an opponent and a result'), findsOneWidget);
    await tester.tap(find.text('I won'));
    await tester.pumpAndSettle();
    expect(find.text('Bogdan'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Save game'));
    await tester.pumpAndSettle();

    expect(repo.me!.rating, greaterThan(before));
    expect(find.textContaining('Game saved. You\'re now ${repo.me!.rating}'), findsOneWidget);
    expect(find.text('Today\'s ladder'), findsOneWidget);
  });

  for (final spec in designs) {
    testWidgets('${spec.name}: every screen renders at 360px', (tester) async {
      _phone(tester);
      final repo = await _signedIn();
      await repo.updateProfile(design: spec.id);
      await tester.pumpWidget(AwakeApp(repository: repo));
      await tester.pumpAndSettle();

      for (final tab in ['Record game', 'History', 'You']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Design'), findsOneWidget);

      // Back to the ladder, then open another player's profile.
      await tester.tap(find.text('Ladder').last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Bogdan').first);
      await tester.pumpAndSettle();
      expect(find.text('Rating over time'), findsOneWidget);
      expect(find.textContaining('Record a game with'), findsOneWidget);
    });
  }

  testWidgets('picking a design in Settings re-skins the app', (tester) async {
    _phone(tester, width: 400);
    final repo = await _signedIn();
    await tester.pumpWidget(AwakeApp(repository: repo, initialLocation: '/settings'));
    await tester.pumpAndSettle();

    final option = find.bySemanticsLabel(RegExp('^Bauhaus design'));
    await tester.scrollUntilVisible(option, 200, scrollable: _list);
    await tester.tap(option);
    await tester.pumpAndSettle();

    expect(repo.me!.design, bauhaus.id);
    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.scaffoldBackgroundColor, bauhaus.background);
  });

  testWidgets('signing out returns to sign-in', (tester) async {
    _phone(tester);
    final repo = await _signedIn();
    await tester.pumpWidget(AwakeApp(repository: repo, initialLocation: '/settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sign out'), 200, scrollable: _list);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });
}
