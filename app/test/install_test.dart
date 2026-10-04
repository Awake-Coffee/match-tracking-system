import 'package:awake_ladder/app.dart';
import 'package:awake_ladder/ui/install/installer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ladder_fixture.dart';

/// An installer whose route the test sets, recording each install.
class _FakeInstaller extends Installer {
  _FakeInstaller(this._route, {this.accept = true});

  InstallRoute _route;
  final bool accept;
  int installs = 0;

  @override
  InstallRoute get route => _route;

  set route(InstallRoute route) {
    _route = route;
    notifyListeners();
  }

  @override
  Future<bool> install() async {
    installs++;
    // The browser offers its dialog once, whatever the answer.
    route = InstallRoute.none;
    return accept;
  }
}

void _screen(WidgetTester tester, {double width = 390}) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _open(
  WidgetTester tester,
  Installer installer, {
  String at = '/',
}) async {
  final repo = await anaAndBogdan();
  await tester.pumpWidget(
    AwakeApp(repository: repo, installer: installer, initialLocation: at),
  );
  await tester.pumpAndSettle();
}

const _offer = 'Keep the ladder on your phone';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a phone that can install is offered the app', (tester) async {
    _screen(tester);
    final installer = _FakeInstaller(InstallRoute.prompt);
    await _open(tester, installer);

    expect(find.text(_offer), findsOneWidget);
    expect(find.text('It opens full screen, like any other app.'), findsOne);
    await tester.tap(find.widgetWithText(FilledButton, 'Install'));
    await tester.pumpAndSettle();

    expect(installer.installs, 1);
    expect(find.text(_offer), findsNothing);
  });

  testWidgets('declining the browser\'s dialog counts as not now', (
    tester,
  ) async {
    _screen(tester);
    final installer = _FakeInstaller(InstallRoute.prompt, accept: false);
    await _open(tester, installer);

    await tester.tap(find.widgetWithText(FilledButton, 'Install'));
    await tester.pumpAndSettle();
    expect(find.text(_offer), findsNothing);
    expect(await InstallOffer.snoozed(), isTrue);
  });

  testWidgets('an iPhone is told how, with no button to press', (tester) async {
    _screen(tester);
    await _open(tester, _FakeInstaller(InstallRoute.shareSheet));

    expect(find.text(_offer), findsOneWidget);
    expect(
      find.text('In Safari, tap Share, then Add to Home Screen.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Install'), findsNothing);
  });

  testWidgets('not now keeps the offer away on the next visit', (tester) async {
    _screen(tester);
    await _open(tester, _FakeInstaller(InstallRoute.prompt));

    await tester.tap(find.byTooltip('Not now'));
    await tester.pumpAndSettle();
    expect(find.text(_offer), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await _open(tester, _FakeInstaller(InstallRoute.prompt));
    expect(find.text(_offer), findsNothing);
  });

  test('not now lasts thirty days', () async {
    final day = DateTime(2026, 10, 4);
    await InstallOffer.snooze(now: day);
    expect(
      await InstallOffer.snoozed(now: day.add(const Duration(days: 29))),
      isTrue,
    );
    expect(
      await InstallOffer.snoozed(now: day.add(const Duration(days: 31))),
      isFalse,
    );
  });

  testWidgets('nothing is offered where the browser can\'t install', (
    tester,
  ) async {
    _screen(tester);
    await _open(tester, _FakeInstaller(InstallRoute.none));
    expect(find.text(_offer), findsNothing);
  });

  testWidgets('wide screens get no banner', (tester) async {
    _screen(tester, width: 1200);
    await _open(tester, _FakeInstaller(InstallRoute.prompt));
    expect(find.text(_offer), findsNothing);
  });

  testWidgets('settings can install after the banner was put off', (
    tester,
  ) async {
    _screen(tester);
    final installer = _FakeInstaller(InstallRoute.prompt);
    await InstallOffer.snooze();
    await _open(tester, installer, at: '/settings');

    expect(find.text(_offer), findsNothing);
    final install = find.widgetWithText(OutlinedButton, 'Install the app');
    await tester.scrollUntilVisible(
      install,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(install);
    await tester.pumpAndSettle();
    expect(installer.installs, 1);
    // Installed: nothing left to offer.
    expect(install, findsNothing);
  });

  testWidgets('settings say nothing once installed', (tester) async {
    _screen(tester);
    await _open(tester, _FakeInstaller(InstallRoute.none), at: '/settings');
    expect(find.text('On your phone'), findsNothing);
  });
}
