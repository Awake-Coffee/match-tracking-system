import 'package:awake_ladder/app.dart';
import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/ui/ladder/counter_ladder.dart';
import 'package:awake_ladder/ui/navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ladder_fixture.dart';

/// What the app tells the browser's history: each address it shows, and
/// whether it replaced the current entry rather than adding one.
typedef _Entry = ({String uri, bool replace});

/// Records the addresses the app reports, as the web engine would turn them
/// into browser history entries.
List<_Entry> _browserHistory(WidgetTester tester) {
  final entries = <_Entry>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.navigation,
    (call) async {
      if (call.method == 'routeInformationUpdated') {
        final args = call.arguments as Map;
        entries.add((
          uri: args['uri'] as String,
          replace: args['replace'] as bool,
        ));
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      null,
    ),
  );
  return entries;
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<String> _idOf(DemoLadderRepository repo, String name) async =>
    (await repo.members()).firstWhere((p) => p.displayName == name).id;

Future<void> _signInAsAna(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), anaEmail);
  await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'x');
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('every page opened is a new entry in the browser history', (
    tester,
  ) async {
    _tall(tester);
    final repo = await anaAndBogdan();
    final bogdan = await _idOf(repo, 'Bogdan');
    final history = _browserHistory(tester);
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(modeLine('Standard'));
    await tester.pumpAndSettle();
    expect(history.last, (uri: '/ladder/standard', replace: false));

    await tester.tap(
      find
          .descendant(
            of: find.byType(CounterLadder),
            matching: find.textContaining('BOGDAN'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('RATING OVER TIME'), findsOneWidget);
    expect(history.last, (
      uri: '/players/$bogdan?mode=standard',
      replace: false,
    ));

    await tester.tap(find.text('You').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Save name'), findsOneWidget);
    expect(history.last, (uri: '/settings', replace: false));
    expect(history.map((e) => e.uri), [
      '/',
      '/ladder/standard',
      '/players/$bogdan?mode=standard',
      '/me',
      '/settings',
    ]);
  });

  testWidgets('a name in the history links to that player\'s address', (
    tester,
  ) async {
    _tall(tester);
    final repo = await anaAndBogdan();
    final bogdan = await _idOf(repo, 'Bogdan');
    final history = _browserHistory(tester);
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/history'),
    );
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('Bogdan'));
    await tester.pumpAndSettle();

    expect(find.text('RATING OVER TIME'), findsOneWidget);
    expect(history.last, (
      uri: '/players/$bogdan?mode=standard',
      replace: false,
    ));
  });

  testWidgets('a shared profile link opens it, and Back goes to the ladder', (
    tester,
  ) async {
    _tall(tester);
    final repo = await anaAndBogdan();
    final bogdan = await _idOf(repo, 'Bogdan');
    final history = _browserHistory(tester);
    await tester.pumpWidget(
      AwakeApp(
        repository: repo,
        initialLocation: '/backgammon/players/$bogdan',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Backgammon rating'), findsOneWidget);
    expect(find.textContaining('with Bogdan'), findsOneWidget);

    // Nothing in the app came before it, so Back can't leave the site.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Rating over time'), findsNothing);
    expect(history.last.uri, '/backgammon');
  });

  testWidgets('a link opened signed out is where signing in leads', (
    tester,
  ) async {
    _tall(tester);
    final repo = await anaAndBogdan();
    final bogdan = await _idOf(repo, 'Bogdan');
    await repo.signOut();
    final history = _browserHistory(tester);
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/swu/players/$bogdan'),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(
      history.last.uri,
      '/sign-in?from=${Uri.encodeQueryComponent('/swu/players/$bogdan')}',
    );

    await _signInAsAna(tester);
    expect(find.text('Star Wars: Unlimited rating'), findsOneWidget);
    expect(find.textContaining('with Bogdan'), findsOneWidget);
    // In place of the sign-in page, which Back would only bounce off.
    expect(history.last, (uri: '/swu/players/$bogdan', replace: true));
  });

  testWidgets('signing out and back in starts at the ladder', (tester) async {
    _tall(tester);
    final repo = await anaAndBogdan();
    final history = _browserHistory(tester);
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/settings'),
    );
    await tester.pumpAndSettle();
    await repo.signOut();
    await tester.pumpAndSettle();
    expect(history.last, (uri: '/sign-in', replace: true));

    await _signInAsAna(tester);
    expect(find.text('LADDERS'), findsOneWidget);
    expect(history.last, (uri: '/', replace: true));
  });

  testWidgets('a filtered history is an address of its own', (tester) async {
    _tall(tester);
    final repo = await anaAndBogdan();
    final bogdan = await _idOf(repo, 'Bogdan');
    final history = _browserHistory(tester);
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/history'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Bogdan').last);
    await tester.pumpAndSettle();
    expect(history.last, (uri: '/history?player=$bogdan', replace: false));

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Everyone').last);
    await tester.pumpAndSettle();
    expect(history.last, (uri: '/history', replace: false));
  });

  testWidgets('a filtered history link opens filtered', (tester) async {
    _tall(tester);
    final repo = await anaAndBogdan();
    await repo.signOut();
    await repo.signUp(
      email: 'cleo@example.com',
      password: 'x',
      displayName: 'Cleo',
    );
    final cleo = repo.me!.id;
    await repo.signOut();
    await repo.signIn(email: anaEmail, password: 'x');
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/history?player=$cleo'),
    );
    await tester.pumpAndSettle();

    expect(find.text('No games for this player yet.'), findsOneWidget);
    final filter = tester.widget<TextField>(
      find.descendant(
        of: find.byType(DropdownMenu<String>),
        matching: find.byType(TextField),
      ),
    );
    expect(filter.controller!.text, 'Cleo');
  });

  testWidgets('an unknown address says so and leads to the ladder', (
    tester,
  ) async {
    _tall(tester);
    final repo = await anaAndBogdan();
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/no-such-page'),
    );
    await tester.pumpAndSettle();
    expect(find.text('There\'s no page at this address.'), findsOneWidget);

    await tester.tap(find.text('Go to the ladder'));
    await tester.pumpAndSettle();
    expect(find.text('LADDERS'), findsOneWidget);
  });

  testWidgets('an unknown address opened signed out keeps it after sign-in', (
    tester,
  ) async {
    _tall(tester);
    final repo = await anaAndBogdan();
    await repo.signOut();
    final history = _browserHistory(tester);
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/backgammon/nope'),
    );
    await tester.pumpAndSettle();
    await _signInAsAna(tester);

    expect(find.text('There\'s no page at this address.'), findsOneWidget);
    expect(history.last, (uri: '/backgammon/nope', replace: true));
    // Within the game's own screens, so its ladder is one tap away.
    await tester.tap(find.text('Go to the ladder'));
    await tester.pumpAndSettle();
    expect(history.last, (uri: '/backgammon', replace: false));
    expect(find.text('Backgammon'), findsWidgets);
  });

  test('sign-in only returns to paths within the app', () {
    expect(returnPath('/players/x?y=1'), '/players/x?y=1');
    expect(returnPath(null), isNull);
    expect(returnPath('https://example.com/'), isNull);
    expect(returnPath('//example.com/'), isNull);
    expect(returnPath(r'/\example.com/'), isNull);
  });
}
