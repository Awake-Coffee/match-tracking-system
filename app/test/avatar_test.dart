import 'package:awake_ladder/app.dart';
import 'package:awake_ladder/ui/widgets/avatar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ladder_fixture.dart';

/// Photos loading from [url].
Finder _photo(String url) => find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is NetworkImage &&
      (w.image as NetworkImage).url == url,
);

/// Tiles standing in with [letter] for a member without a photo.
Finder _initial(String letter) =>
    find.descendant(of: find.byType(Avatar), matching: find.text(letter));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a photo shows on the profile, ladder and results; others get '
      'their initial', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = await anaAndBogdan();
    await repo.updateAvatar(
      Uint8List.fromList([1, 2, 3]),
      contentType: 'image/png',
    );
    final url = repo.me!.avatarUrl!;
    expect(url, startsWith('data:image/png'));

    await tester.pumpWidget(AwakeApp(repository: repo, initialLocation: '/me'));
    await tester.pumpAndSettle();
    expect(_photo(url), findsOneWidget, reason: 'Ana\'s profile header');
    expect(_initial('B'), findsWidgets, reason: 'her result against Bogdan');

    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/ladder/standard'),
    );
    await tester.pumpAndSettle();
    expect(_photo(url), findsWidgets, reason: 'Ana\'s ladder line');
    expect(_initial('B'), findsWidgets, reason: 'Bogdan\'s ladder line');
  });

  testWidgets('settings takes the photo down', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = await anaAndBogdan();
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/settings'),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Add photo'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Remove'), findsNothing);

    await repo.updateAvatar(
      Uint8List.fromList([1, 2, 3]),
      contentType: 'image/jpeg',
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Change photo'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(repo.me!.avatarUrl, isNull);
    expect(find.text('Photo removed.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add photo'), findsOneWidget);
    expect(_initial('A'), findsOneWidget);
  });
}
