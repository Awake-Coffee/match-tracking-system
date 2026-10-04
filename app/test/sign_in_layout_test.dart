import 'package:awake_ladder/app.dart';
import 'package:awake_ladder/ui/screens/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ladder_fixture.dart';

// Its own file because fonts register for the whole test process: measuring
// with the real faces here leaves app_test.dart on the square test font.

/// Registers the sign-in screen's bundled faces so wrapping matches a phone.
Future<void> _loadFonts() async {
  final faces = {
    'Gloock': ['Gloock-Regular'],
    'Karla': ['Karla-Regular', 'Karla-Medium', 'Karla-SemiBold', 'Karla-Bold'],
  };
  for (final MapEntry(key: family, value: files) in faces.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load('assets/fonts/$file.ttf'));
    }
    await loader.load();
  }
}

void main() {
  // A Text that wraps never throws, so check the outcome: at most four lines
  // of headline, and the Sign in button on screen without scrolling.
  testWidgets('the spelled-out headline fits a 360px phone', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = await anaAndBogdan();
    await repo.signOut();
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    final headline = find.text('Chess, backgammon and Star Wars: Unlimited');
    final style = tester.widget<Text>(headline).style!;
    final line = style.fontSize! * style.height!;

    expect(tester.getSize(headline).height, lessThanOrEqualTo(4 * line + 1));
    expect(
      tester.getRect(find.widgetWithText(FilledButton, 'Sign in')).bottom,
      lessThanOrEqualTo(800),
    );
  });

  // Same eyebrow and headline scale as sign-in, so the same phone check.
  testWidgets('the reset page fits a 360px phone', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = await anaAndBogdan();
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/reset-password'),
    );
    await tester.pumpAndSettle();

    final headline = find.text('Choose a new password');
    final style = tester.widget<Text>(headline).style!;
    final line = style.fontSize! * style.height!;

    expect(style.fontSize, authHeadlineSize);
    expect(tester.getSize(headline).height, lessThanOrEqualTo(2 * line + 1));
    expect(
      tester.getRect(find.text('Cancel and sign out')).bottom,
      lessThanOrEqualTo(800),
    );
  });
}
