import 'package:awake_ladder/app.dart';
import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/data/ladder_repository.dart';
import 'package:awake_ladder/domain/backgammon.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:awake_ladder/domain/swu.dart';
import 'package:awake_ladder/design/design_scope.dart';
import 'package:awake_ladder/design/designs.dart';
import 'package:awake_ladder/ui/ladder/baize_ladder.dart';
import 'package:awake_ladder/ui/ladder/pawns_ladder.dart';
import 'package:awake_ladder/ui/ladder/route_ladder.dart';
import 'package:awake_ladder/ui/widgets/match_request_list.dart';
import 'package:awake_ladder/ui/widgets/match_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // The chess form remembers the last clock in browser storage.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('signing in lands on the ladder', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await repo.signOut();
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('Chess, backgammon and SWU'), findsOneWidget);
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

  /// Opens the app signed out and submits the sign-up form for [email].
  Future<void> signUpAs(
    WidgetTester tester,
    DemoLadderRepository repo,
    String email,
  ) async {
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New here? Create a profile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Display name'),
      'Cleo',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'longenough',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create profile'));
    await tester.pumpAndSettle();
  }

  testWidgets('a sign-up that needs confirming is a success, not an error', (
    tester,
  ) async {
    _phone(tester);
    final repo = DemoLadderRepository()..requireEmailConfirmation = true;
    await signUpAs(tester, repo, 'cleo@example.com');

    expect(repo.isSignedIn, isFalse);
    expect(find.text('Check your inbox'), findsOneWidget);
    expect(find.text('cleo@example.com'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create profile'), findsNothing);
    final loss = tester.element(find.text('Check your inbox')).design.loss;
    final colours = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.style?.color);
    expect(colours, isNot(contains(loss)));
  });

  testWidgets('resend waits out the sign-up email\'s rate limit', (
    tester,
  ) async {
    _phone(tester);
    final repo = DemoLadderRepository()..requireEmailConfirmation = true;
    await signUpAs(tester, repo, 'cleo@example.com');

    final waiting = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'You can resend in a minute'),
    );
    expect(waiting.onPressed, isNull);
    expect(find.widgetWithText(TextButton, 'Resend email'), findsNothing);

    await tester.pump(const Duration(seconds: 61));
    final ready = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Resend email'),
    );
    expect(ready.onPressed, isNotNull);
  });

  testWidgets('resending the confirmation acknowledges, then waits', (
    tester,
  ) async {
    _phone(tester);
    final repo = DemoLadderRepository()..requireEmailConfirmation = true;
    await signUpAs(tester, repo, ' Cleo@Example.com ');
    await tester.pump(const Duration(seconds: 61));

    await tester.tap(find.widgetWithText(TextButton, 'Resend email'));
    await tester.pump();
    await tester.pump();
    expect(repo.resentConfirmations, ['cleo@example.com']);
    final sent = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Sent again'),
    );
    expect(sent.onPressed, isNull);

    await tester.pump(const Duration(seconds: 61));
    final again = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Resend email'),
    );
    expect(again.onPressed, isNotNull);
  });

  testWidgets('a failed resend is an error and can be retried', (tester) async {
    _phone(tester);
    final repo = DemoLadderRepository()
      ..requireEmailConfirmation = true
      ..resendError = const LadderException(
        'Give it a minute, then try again.',
      );
    await signUpAs(tester, repo, 'cleo@example.com');
    await tester.pump(const Duration(seconds: 61));

    await tester.tap(find.widgetWithText(TextButton, 'Resend email'));
    await tester.pump();
    await tester.pump();
    final error = find.text('Give it a minute, then try again.');
    expect(error, findsOneWidget);
    final loss = tester.element(error).design.loss;
    expect(tester.widget<Text>(error).style?.color, loss);
    expect(find.text('Sent again'), findsNothing);
    final retry = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Resend email'),
    );
    expect(retry.onPressed, isNotNull);
  });

  testWidgets('back to sign in keeps the email and lets them sign in', (
    tester,
  ) async {
    _phone(tester);
    final repo = DemoLadderRepository()..requireEmailConfirmation = true;
    await signUpAs(tester, repo, 'cleo@example.com');

    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Check your inbox'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('cleo@example.com'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'longenough',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('The ladder'), findsOneWidget);
  });

  testWidgets('a failed sign-up stays an error in the loss colour', (
    tester,
  ) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await repo.signOut();
    await signUpAs(tester, repo, anaEmail);

    expect(find.text('Check your inbox'), findsNothing);
    final error = find.text(
      'That email already has an account. Sign in instead.',
    );
    expect(error, findsOneWidget);
    final loss = tester.element(error).design.loss;
    expect(tester.widget<Text>(error).style?.color, loss);
  });

  /// Opens the app signed out and asks for a reset link for [email].
  Future<void> forgotPasswordFor(
    WidgetTester tester,
    DemoLadderRepository repo,
    String email,
  ) async {
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
    await tester.tap(find.widgetWithText(FilledButton, 'Send reset link'));
    await tester.pumpAndSettle();
  }

  testWidgets('forgot password sends a link and says where it went', (
    tester,
  ) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await repo.signOut();
    await forgotPasswordFor(tester, repo, ' $anaEmail ');

    expect(repo.passwordResets, [anaEmail]);
    expect(find.text('Check your inbox'), findsOneWidget);
    expect(find.text('We sent a link to'), findsOneWidget);
    expect(find.text(anaEmail), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email'), findsNothing);

    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Check your inbox'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text(anaEmail), findsOneWidget);
  });

  testWidgets('forgot password can be retried with another email', (
    tester,
  ) async {
    _phone(tester);
    final repo = DemoLadderRepository();
    await forgotPasswordFor(tester, repo, 'typo@example.com');

    await tester.tap(find.text('Use a different email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'right@example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send reset link'));
    await tester.pumpAndSettle();
    expect(repo.passwordResets, ['typo@example.com', 'right@example.com']);
  });

  testWidgets('forgot password asks for an email and shows send failures', (
    tester,
  ) async {
    _phone(tester);
    final repo = DemoLadderRepository()
      ..passwordResetError = const LadderException('Give it a minute.');
    await forgotPasswordFor(tester, repo, 'nope');
    expect(find.text('Enter an email address'), findsOneWidget);
    expect(repo.passwordResets, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'ana@example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send reset link'));
    await tester.pumpAndSettle();
    final error = find.text('Give it a minute.');
    expect(error, findsOneWidget);
    expect(
      tester.widget<Text>(error).style?.color,
      tester.element(error).design.loss,
    );
    expect(find.text('Check your inbox'), findsNothing);
  });

  testWidgets('every password field can show and hide what is typed', (
    tester,
  ) async {
    _phone(tester);
    final repo = DemoLadderRepository();
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    bool obscured() => tester
        .widget<EditableText>(
          find.descendant(
            of: find.widgetWithText(TextFormField, 'Password'),
            matching: find.byType(EditableText),
          ),
        )
        .obscureText;
    expect(obscured(), isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(obscured(), isFalse);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(obscured(), isTrue);

    // Creating a profile has the same field.
    await tester.tap(find.text('New here? Create a profile'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show password'), findsOneWidget);
  });

  testWidgets('a recovery link lands on a new-password form, then the ladder', (
    tester,
  ) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await repo.signOut();
    await repo.openRecoveryLink(anaEmail);
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    expect(repo.passwordRecoveryPending, isTrue);
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(find.text('The ladder'), findsNothing);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'short');
    await tester.enterText(fields.at(1), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Save password'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters'), findsOneWidget);

    await tester.enterText(fields.at(0), 'longenough');
    await tester.enterText(fields.at(1), 'different1');
    await tester.tap(find.widgetWithText(FilledButton, 'Save password'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords don\'t match'), findsOneWidget);
    expect(repo.passwordChanges, isEmpty);

    await tester.enterText(fields.at(1), 'longenough');
    await tester.tap(find.widgetWithText(FilledButton, 'Save password'));
    await tester.pumpAndSettle();
    expect(repo.passwordChanges, [anaEmail]);
    expect(repo.passwordRecoveryPending, isFalse);
    expect(find.text('The ladder'), findsOneWidget);
    expect(find.textContaining('You\'re '), findsOneWidget);
  });

  testWidgets('a recovery in progress cannot wander off to the ladder', (
    tester,
  ) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await repo.signOut();
    await repo.openRecoveryLink(anaEmail);
    await tester.pumpWidget(AwakeApp(repository: repo, initialLocation: '/me'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);
  });

  testWidgets('a recovery link opened while sign-in is showing', (
    tester,
  ) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await repo.signOut();
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);

    // Supabase can replay the recovery event after the router has started.
    await repo.openRecoveryLink(anaEmail);
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);
  });

  testWidgets('a broken recovery link explains itself and asks again', (
    tester,
  ) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await repo.signOut();
    repo.openBrokenRecoveryLink();
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    final error = find.text(brokenResetLinkMessage);
    expect(error, findsOneWidget);
    expect(
      tester.widget<Text>(error).style?.color,
      tester.element(error).design.loss,
    );
    final email = find.widgetWithText(TextFormField, 'Email');
    expect(email, findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsNothing);

    await tester.enterText(email, anaEmail);
    await tester.tap(find.widgetWithText(FilledButton, 'Send reset link'));
    await tester.pumpAndSettle();
    expect(repo.passwordResets, [anaEmail]);
    expect(repo.authLinkError, isNull);
    expect(find.text(brokenResetLinkMessage), findsNothing);
    expect(
      find.textContaining('on this device, in this browser'),
      findsOneWidget,
    );

    // "Use a different email" returns to the reset form, not sign-in.
    await tester.tap(find.text('Use a different email'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, 'Send reset link'),
      findsOneWidget,
    );
  });

  testWidgets('a broken recovery link can be left for sign-in', (tester) async {
    _phone(tester);
    final repo = DemoLadderRepository()..openBrokenRecoveryLink();
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    expect(repo.authLinkError, isNull);
    expect(find.text(brokenResetLinkMessage), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('the reset page signed out goes to sign-in', (tester) async {
    _phone(tester);
    final repo = DemoLadderRepository();
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/reset-password'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('a reloaded reset page keeps its form, then goes to the ladder', (
    tester,
  ) async {
    _phone(tester);
    // Signed in by the recovery link, but the reload forgot the recovery.
    final repo = await anaAndBogdan();
    expect(repo.passwordRecoveryPending, isFalse);
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/reset-password'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'longenough');
    await tester.enterText(fields.at(1), 'longenough');
    await tester.tap(find.widgetWithText(FilledButton, 'Save password'));
    await tester.pumpAndSettle();
    expect(repo.passwordChanges, [anaEmail]);
    expect(find.text('The ladder'), findsOneWidget);
  });

  testWidgets('cancelling a recovery signs out', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await repo.signOut();
    await repo.openRecoveryLink(anaEmail);
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel and sign out'));
    await tester.pumpAndSettle();
    expect(repo.passwordRecoveryPending, isFalse);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
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
    await tester.tap(find.text('White'));
    final more = find.widgetWithText(ChoiceChip, 'More…');
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
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
    expect(find.text('Pick the custom time'), findsOneWidget);
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

  group('chess time control', () {
    final send = find.widgetWithText(FilledButton, 'Send for confirmation');
    Finder chip(String label) => find.widgetWithText(ChoiceChip, label);

    Future<void> open(
      WidgetTester tester,
      DemoLadderRepository repo, {
      String location = '/record',
    }) async {
      _phone(tester);
      await tester.pumpWidget(
        AwakeApp(repository: repo, initialLocation: location),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapVisible(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('the hint lists what is still missing', (tester) async {
      await open(tester, await anaAndBogdan());
      await tester.ensureVisible(send);
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      expect(
        find.text(
          'Pick an opponent, a result, the colour you played '
          'and a time control',
        ),
        findsOneWidget,
      );

      await tapVisible(tester, find.text('I won'));
      expect(
        find.text('Pick an opponent, the colour you played and a time control'),
        findsOneWidget,
      );
    });

    testWidgets('the colour starts unchosen and gates the button', (
      tester,
    ) async {
      final repo = SharedLadder();
      await anaAndBogdan(into: repo);
      await open(tester, repo, location: '/record?opponent=demo-2');
      await tapVisible(tester, find.text('I won'));
      await tapVisible(tester, chip('Sudden death 5 min'));

      expect(
        tester
            .widget<SegmentedButton<PieceColor>>(
              find.byType(SegmentedButton<PieceColor>),
            )
            .selected,
        isEmpty,
      );
      expect(find.text('Pick the colour you played'), findsOneWidget);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);

      await tapVisible(tester, find.text('Black'));

      expect(find.textContaining('Pick'), findsNothing);
      expect(tester.widget<FilledButton>(send).onPressed, isNotNull);

      // The choice must reach the stored report: White, the old default,
      // would pass every test that only checks the button.
      final anaId = repo.me!.id;
      await tapVisible(tester, send);
      final sent = (await repo.matchRequests()).singleWhere(
        (r) => r.requestedBy == anaId,
      );
      expect(sent.colorOf(anaId), PieceColor.black);
      expect(sent.outcomeFor(anaId), Outcome.win);
    });

    testWidgets('choosing a chip enables the button and clears the hint', (
      tester,
    ) async {
      final repo = SharedLadder();
      await anaAndBogdan(into: repo);
      await open(tester, repo, location: '/record?opponent=demo-2');
      await tapVisible(tester, find.text('I won'));
      await tapVisible(tester, find.text('White'));

      expect(find.text('Pick a time control'), findsOneWidget);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      // Ana has played sudden death 5 min; the Fischer 5 + 3 game against her
      // is Bogdan's report and is still unconfirmed.
      await tapVisible(tester, chip('Sudden death 5 min'));

      expect(find.textContaining('Pick a'), findsNothing);
      expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
    });

    testWidgets('a member with no history gets the default chips', (
      tester,
    ) async {
      final repo = DemoLadderRepository();
      await repo.signUp(email: anaEmail, password: 'x', displayName: 'Ana');
      await repo.signOut();
      await repo.signUp(
        email: bogdanEmail,
        password: 'x',
        displayName: 'Bogdan',
      );
      await open(tester, repo);

      for (final label in [
        'Fischer 5 min + 3 s',
        'Fischer 10 min + 10 s',
        'Fischer 15 min + 10 s',
        'Sudden death 5 min',
        'More…',
      ]) {
        expect(chip(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('the last clock is preselected on the next visit', (
      tester,
    ) async {
      final repo = DemoLadderRepository();
      await anaAndBogdan(into: repo);
      await open(tester, repo, location: '/record?opponent=demo-2');
      await tapVisible(tester, find.text('I won'));
      await tapVisible(tester, find.text('White'));
      await tapVisible(tester, chip('More…'));
      await tester.tap(find.byType(DropdownMenu<TimeControl>));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Fischer custom').last);
      await tester.enterText(
        find.widgetWithText(TextField, 'Minutes each'),
        '7',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Increment (s)'),
        '4',
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, send);
      expect(find.textContaining('Sent to Bogdan'), findsOneWidget);

      // A later visit, with the pending request not yet confirmed: only the
      // stored preference knows the custom clock.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        AwakeApp(repository: repo, initialLocation: '/record?opponent=demo-2'),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<ChoiceChip>(chip('Fischer 7 min + 4 s')).selected,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Minutes each'))
            .controller!
            .text,
        '7',
      );
      await tapVisible(tester, find.text('I won'));
      await tapVisible(tester, find.text('White'));
      expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
    });

    testWidgets('a clock recorded on another device shows as a chip', (
      tester,
    ) async {
      // No stored preference: the chip comes from the member's own games.
      await open(tester, await anaAndBogdan());
      expect(chip('Sudden death 5 min'), findsOneWidget);
      expect(
        tester.widget<ChoiceChip>(chip('Sudden death 5 min')).selected,
        isFalse,
      );
    });

    testWidgets('a short history is padded with the defaults', (tester) async {
      // Ana has played one clock; three defaults fill the row to four. The
      // opponent chip for Bogdan sits above them.
      await open(tester, await anaAndBogdan());
      final labels = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((c) => (c.label as Text).data)
          .toList();
      expect(labels, [
        'Bogdan',
        'Sudden death 5 min',
        'Fischer 5 min + 3 s',
        'Fischer 10 min + 10 s',
        'Fischer 15 min + 10 s',
        'More…',
      ]);
    });

    testWidgets('a clock without a chip keeps the full list open', (
      tester,
    ) async {
      await open(tester, await anaAndBogdan());
      await tapVisible(tester, chip('More…'));
      await tester.tap(find.byType(DropdownMenu<TimeControl>));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Fischer 25 min + 10 s').last);
      await tapVisible(tester, chip('More…'));

      expect(tester.widget<ChoiceChip>(chip('More…')).selected, isFalse);
      expect(
        tester
            .widget<DropdownMenu<TimeControl>>(
              find.byType(DropdownMenu<TimeControl>),
            )
            .initialSelection,
        TimeControl.fischer25plus10,
      );

      // A chip's clock needs no list.
      await tapVisible(tester, chip('Sudden death 5 min'));
      expect(find.byType(DropdownMenu<TimeControl>), findsNothing);
    });

    testWidgets('the stored clock leads the clocks of past games', (
      tester,
    ) async {
      final repo = _CountedGames();
      await anaAndBogdan(into: repo);
      SharedPreferences.setMockInitialValues({
        'last_clock.${repo.me!.id}': '21,7,4',
      });
      await open(tester, repo);

      expect(
        tester.widget<ChoiceChip>(chip('Fischer 7 min + 4 s')).selected,
        isTrue,
      );
      expect(chip('Sudden death 5 min'), findsOneWidget);
      // One fetch of Ana's games feeds both the opponent and the clock chips.
      expect(repo.ownGamesFetches, 1);
    });
  });

  testWidgets('backgammon and SWU forms say what is still missing', (
    tester,
  ) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    final send = find.widgetWithText(FilledButton, 'Send for confirmation');
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/backgammon/record'),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    expect(
      find.text('Pick an opponent, a result and the loser\'s points'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      AwakeApp(
        repository: repo,
        initialLocation: '/swu/record?opponent=demo-2',
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    expect(find.text('Pick a result'), findsOneWidget);
    await tester.tap(find.text('I won'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    expect(find.text('Pick the games'), findsOneWidget);
  });

  group('recent opponents', () {
    Finder chip(String name) => find.widgetWithText(ChoiceChip, name);
    final recentLabel = find.text('Recent opponents');
    final picker = find.byType(DropdownMenu<String>);
    String fieldText(WidgetTester tester) => tester
        .widget<TextField>(
          find.descendant(of: picker, matching: find.byType(TextField)),
        )
        .controller!
        .text;

    Future<void> open(
      WidgetTester tester,
      DemoLadderRepository repo,
      String location,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        AwakeApp(repository: repo, initialLocation: location),
      );
      await tester.pumpAndSettle();
    }

    /// Ana plus five others; unless [report] is false, she reports SWU matches
    /// against Bea, Cal, Dan, Eve and Fay, then Cal again, all still pending.
    Future<DemoLadderRepository> regulars({bool report = true}) async {
      final repo = DemoLadderRepository();
      await repo.signUp(email: anaEmail, password: 'x', displayName: 'Ana');
      await repo.signOut();
      final ids = <String>[];
      for (final name in ['Bea', 'Cal', 'Dan', 'Eve', 'Fay']) {
        await repo.signUp(
          email: '$name@example.com',
          password: 'x',
          displayName: name,
        );
        ids.add(repo.me!.id);
        await repo.signOut();
      }
      await repo.signIn(email: anaEmail, password: 'x');
      for (final i in report ? [0, 1, 2, 3, 4, 1] : const <int>[]) {
        await repo.requestSwuMatch(
          opponentId: ids[i],
          myGames: 2,
          opponentGames: 0,
        );
      }
      return repo;
    }

    for (final (game, location) in [
      ('chess', '/record'),
      ('backgammon', '/backgammon/record'),
      ('SWU', '/swu/record'),
    ]) {
      testWidgets('the $game form offers them and a chip picks one', (
        tester,
      ) async {
        final repo = await anaAndBogdanWithSwu();
        await open(tester, repo, location);

        expect(recentLabel, findsOneWidget);
        expect(chip('Bogdan'), findsOneWidget);
        expect(tester.widget<ChoiceChip>(chip('Bogdan')).selected, isFalse);
        expect(fieldText(tester), isEmpty);

        await tester.tap(chip('Bogdan'));
        await tester.pumpAndSettle();

        expect(tester.widget<ChoiceChip>(chip('Bogdan')).selected, isTrue);
        expect(fieldText(tester), 'Bogdan');
      });
    }

    testWidgets('picking from the menu highlights the matching chip', (
      tester,
    ) async {
      await open(tester, await anaAndBogdan(), '/record');

      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Bogdan'));
      await tester.pumpAndSettle();

      expect(tester.widget<ChoiceChip>(chip('Bogdan')).selected, isTrue);
    });

    testWidgets('a pre-chosen opponent starts highlighted', (tester) async {
      await open(tester, await anaAndBogdan(), '/record?opponent=demo-2');

      expect(tester.widget<ChoiceChip>(chip('Bogdan')).selected, isTrue);
    });

    testWidgets('they are the latest four, newest first, each once', (
      tester,
    ) async {
      await open(tester, await regulars(), '/swu/record');

      final names = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((c) => (c.label as Text).data)
          .toList();
      // Reported Bea, Cal, Dan, Eve, Fay, then Cal again: Bea falls off.
      expect(names, ['Cal', 'Fay', 'Eve', 'Dan']);
    });

    testWidgets('confirmed and pending results merge by time; declined do not '
        'count', (tester) async {
      final repo = await regulars(report: false);
      final ids = {for (final p in await repo.ladder()) p.displayName: p.id};
      Future<void> report(String name) => repo.requestSwuMatch(
        opponentId: ids[name]!,
        myGames: 2,
        opponentGames: 0,
      );
      Future<void> answer(String name, {required bool accept}) async {
        await repo.signIn(email: '$name@example.com', password: 'x');
        final request = (await repo.swuMatchRequests()).single;
        await repo.respondToSwuMatchRequest(request.id, accept: accept);
        await repo.signIn(email: anaEmail, password: 'x');
      }

      await report('Cal'); // pending
      await report('Bea');
      await answer('Bea', accept: true); // confirmed, newer than Cal's
      await report('Eve'); // pending, newest that counts
      await report('Dan');
      await answer('Dan', accept: false); // declined
      await open(tester, repo, '/swu/record');

      final names = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((c) => (c.label as Text).data)
          .toList();
      expect(names, ['Eve', 'Bea', 'Cal']);
    });

    testWidgets('tapping the chosen chip again restores its name', (
      tester,
    ) async {
      await open(tester, await anaAndBogdan(), '/record');
      await tester.tap(chip('Bogdan'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: picker, matching: find.byType(TextField)),
        'Bo',
      );
      await tester.pumpAndSettle();

      await tester.tap(chip('Bogdan'));
      await tester.pumpAndSettle();

      expect(fieldText(tester), 'Bogdan');
      expect(tester.widget<ChoiceChip>(chip('Bogdan')).selected, isTrue);
    });

    testWidgets('a member with no history sees no extras', (tester) async {
      final repo = DemoLadderRepository();
      await repo.signUp(email: anaEmail, password: 'x', displayName: 'Ana');
      await repo.signOut();
      await repo.signUp(
        email: bogdanEmail,
        password: 'x',
        displayName: 'Bogdan',
      );
      for (final location in ['/record', '/backgammon/record', '/swu/record']) {
        await open(tester, repo, location);
        expect(recentLabel, findsNothing, reason: location);
        expect(chip('Ana'), findsNothing, reason: location);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('games in another game do not count', (tester) async {
      // Bogdan and Ana have only played chess so far.
      final repo = await anaAndBogdan();
      await open(tester, repo, '/swu/record');

      expect(recentLabel, findsNothing);
    });
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

  /// Bogdan reports a draw against Ana from his own device; this client
  /// isn't told.
  Future<void> bogdanReportsADraw(SharedLadder repo) =>
      repo.elsewhere(() async {
        final anaId = repo.me!.id;
        await repo.signIn(email: bogdanEmail, password: 'x');
        await repo.requestMatch(
          opponentId: anaId,
          myColor: PieceColor.black,
          myOutcome: Outcome.draw,
          clock: const ClockSetting(TimeControl.sudden5),
        );
        await repo.signIn(email: anaEmail, password: 'x');
      });

  testWidgets('a result reported elsewhere appears when the repository hears '
      'of it', (tester) async {
    _phone(tester);
    final repo = SharedLadder();
    await anaAndBogdan(into: repo);
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    await bogdanReportsADraw(repo);
    await tester.pumpAndSettle();
    expect(find.text('Bogdan says it was a draw'), findsNothing);
    expect(_awaitingBadge('1'), findsOneWidget);

    // What a Realtime event, the poll or returning to the app does.
    repo.reload();
    await tester.pumpAndSettle();

    expect(find.text('Bogdan says you lost'), findsOneWidget);
    expect(find.text('Bogdan says it was a draw'), findsOneWidget);
    expect(_awaitingBadge('2'), findsOneWidget);
  });

  testWidgets('wide screens refresh from the header', (tester) async {
    _phone(tester, width: 1024);
    final repo = SharedLadder();
    await anaAndBogdan(into: repo);
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();
    await bogdanReportsADraw(repo);
    await tester.pumpAndSettle();
    expect(find.text('Bogdan says it was a draw'), findsNothing);

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('Bogdan says it was a draw'), findsOneWidget);
    expect(_awaitingBadge('2'), findsOneWidget);
  });

  testWidgets('pulling to refresh updates the list and the tab badge', (
    tester,
  ) async {
    _phone(tester);
    final repo = SharedLadder();
    await anaAndBogdan(into: repo);
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();
    await bogdanReportsADraw(repo);

    await tester.fling(_list, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Bogdan says it was a draw'), findsOneWidget);
    expect(_awaitingBadge('2'), findsOneWidget);
  });

  testWidgets('a failed background reload keeps the form and badges', (
    tester,
  ) async {
    _phone(tester);
    final repo = SharedLadder();
    await anaAndBogdan(into: repo);
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/record?opponent=demo-2'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Black'));
    final won = find.text('I won');
    await tester.ensureVisible(won);
    await tester.pumpAndSettle();
    await tester.tap(won);
    await tester.pumpAndSettle();

    repo.offline = true;
    repo.reload();
    await tester.pumpAndSettle();

    expect(find.textContaining('Couldn\'t load this'), findsNothing);
    expect(
      tester
          .widget<SegmentedButton<PieceColor>>(
            find.byType(SegmentedButton<PieceColor>),
          )
          .selected,
      {PieceColor.black},
    );
    expect(
      tester
          .widget<SegmentedButton<Outcome>>(
            find.byType(SegmentedButton<Outcome>),
          )
          .selected,
      {Outcome.win},
    );
    expect(_awaitingBadge('1'), findsOneWidget);
  });

  testWidgets('a failed pull to refresh keeps the list and says so', (
    tester,
  ) async {
    _phone(tester);
    final repo = SharedLadder();
    await anaAndBogdan(into: repo);
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    repo.offline = true;
    await tester.fling(_list, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Bogdan says you lost'), findsOneWidget);
    expect(
      find.text('Couldn\'t refresh. Check your connection.'),
      findsOneWidget,
    );
    expect(_awaitingBadge('1'), findsOneWidget);
  });

  testWidgets('a first load that fails offers to try again', (tester) async {
    _phone(tester);
    final repo = SharedLadder();
    await anaAndBogdan(into: repo);
    repo.offline = true;
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.textContaining('Couldn\'t load this'), findsOneWidget);

    repo.offline = false;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Bogdan says you lost'), findsOneWidget);
    expect(_awaitingBadge('1'), findsOneWidget);
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

    final field = find.widgetWithText(TextFormField, 'Display name');
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

  testWidgets('settings shows the signed-in email', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/settings'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Signed in as $anaEmail'), findsOneWidget);
  });

  testWidgets('changing the password from settings', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/settings'),
    );
    await tester.pumpAndSettle();

    final change = find.widgetWithText(FilledButton, 'Change password');
    await tester.scrollUntilVisible(change, 200, scrollable: _list);
    final newPassword = find.widgetWithText(TextFormField, 'New password');
    final confirm = find.widgetWithText(TextFormField, 'Confirm new password');

    await tester.enterText(newPassword, 'longenough');
    await tester.enterText(confirm, 'longenougH');
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(find.text('Passwords don\'t match'), findsOneWidget);
    expect(repo.passwordChanges, isEmpty);

    await tester.enterText(newPassword, 'short');
    await tester.enterText(confirm, 'short');
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters'), findsOneWidget);

    await tester.enterText(newPassword, 'longenough');
    await tester.enterText(confirm, 'longenough');
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(repo.passwordChanges, [anaEmail]);
    expect(find.text('Password updated.'), findsOneWidget);
    // Stays in Settings, signed in, with the fields emptied.
    expect(find.text('Settings'), findsWidgets);
    expect(repo.isSignedIn, isTrue);
    expect(tester.widget<TextFormField>(newPassword).controller!.text, '');
    expect(tester.widget<TextFormField>(confirm).controller!.text, '');
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

  testWidgets('a member who has not played sits below every ladder unranked', (
    tester,
  ) async {
    _phone(tester);
    final repo = await anaAndBogdanWithSwu();
    await repo.signOut();
    await repo.signUp(
      email: 'cleo@example.com',
      password: 'x',
      displayName: 'Cleo',
    );
    await repo.signOut();
    await repo.signIn(email: anaEmail, password: 'x');
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    Future<void> expectUnranked(Type ladder) async {
      final cleo = find.descendant(
        of: find.byType(ladder),
        matching: find.text('Cleo'),
      );
      await tester.scrollUntilVisible(cleo, 200, scrollable: _list);
      // Listed once, in the muted group, not among the pawns: her row carries
      // no rank number, and the two ranked members are 1st and 2nd.
      expect(cleo, findsOneWidget);
      expect(find.text('Not yet played'), findsOneWidget);
      expect(find.text('3'), findsNothing);
      // The route draws no rank numbers at all, so check what screen readers
      // hear, which every ladder labels the same way.
      expect(find.bySemanticsLabel(RegExp(r'^Cleo, rating')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^\d+(st|nd|rd|th), Cleo')),
        findsNothing,
      );
      expect(find.textContaining('of 2 with'), findsOneWidget);
      await tester.ensureVisible(cleo);
      await tester.pumpAndSettle();
      await tester.tap(cleo);
      await tester.pumpAndSettle();
      expect(find.textContaining('with Cleo'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    await expectUnranked(PawnsLadder);

    await tester.tap(find.byTooltip('Switch game'));
    await tester.pumpAndSettle();
    // Each card counts the two ranked members, not Cleo.
    expect(find.textContaining('1st of 2', findRichText: true), findsWidgets);
    expect(find.textContaining('of 3', findRichText: true), findsNothing);
    await tester.tap(find.text('Backgammon'));
    await tester.pumpAndSettle();
    await expectUnranked(BaizeLadder);

    await tester.tap(find.byTooltip('Switch game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Star Wars: Unlimited'));
    await tester.pumpAndSettle();
    await expectUnranked(RouteLadder);
  });

  testWidgets('every ladder renders when nobody has played yet', (
    tester,
  ) async {
    _phone(tester);
    final repo = DemoLadderRepository();
    await repo.signUp(
      email: 'cleo@example.com',
      password: 'x',
      displayName: 'Cleo',
    );
    await repo.signOut();
    await repo.signUp(email: anaEmail, password: 'x', displayName: 'Ana');
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    Future<void> expectAllWaiting(Type ladder) async {
      expect(find.byType(ladder), findsOneWidget);
      expect(find.textContaining('You start at'), findsOneWidget);
      final cleo = find.descendant(
        of: find.byType(ladder),
        matching: find.text('Cleo'),
      );
      await tester.scrollUntilVisible(cleo, 200, scrollable: _list);
      expect(find.text('Not yet played'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Cleo, rating')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Ana \(you\), rating')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^\d+(st|nd|rd|th), ')),
        findsNothing,
      );
    }

    // No empty top-eight board: the summary leads straight to the group.
    expect(find.text('No games yet.'), findsOneWidget);
    expect(find.textContaining('top eight'), findsNothing);
    await expectAllWaiting(PawnsLadder);

    await tester.tap(find.byTooltip('Switch game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backgammon'));
    await tester.pumpAndSettle();
    await expectAllWaiting(BaizeLadder);

    await tester.tap(find.byTooltip('Switch game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Star Wars: Unlimited'));
    await tester.pumpAndSettle();
    await expectAllWaiting(RouteLadder);
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
    Finder points(int n) => find.widgetWithText(ChoiceChip, '$n');
    await tester.ensureVisible(find.text('I won'));
    // No result picked yet: no points to ask for.
    expect(find.text('Bogdan\'s points'), findsNothing);
    await tester.tap(find.text('I won'));
    await tester.pumpAndSettle();
    // The winner scores the match length, so only the loser's points are asked.
    expect(find.text('Bogdan\'s points'), findsOneWidget);
    expect(points(5), findsNothing);
    await tester.tap(points(1));
    await tester.pumpAndSettle();
    expect(find.text('1500 to '), findsNWidgets(2));
    expect(find.text('+22'), findsOneWidget);

    // A shorter match moves ratings less.
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

  testWidgets('a lost backgammon match asks for your own points', (
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

    final send = find.widgetWithText(FilledButton, 'Send for confirmation');
    Finder points(int n) => find.widgetWithText(ChoiceChip, '$n');
    await tester.ensureVisible(find.text('I lost'));
    await tester.tap(find.text('I lost'));
    await tester.pumpAndSettle();
    expect(find.text('Your points'), findsOneWidget);
    expect(find.text('Bogdan\'s points'), findsNothing);
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    expect(find.text('Pick the loser\'s points'), findsOneWidget);
    expect(tester.widget<FilledButton>(send).onPressed, isNull);

    await tester.ensureVisible(points(4));
    await tester.tap(points(4));
    await tester.pumpAndSettle();
    // A shorter match drops a loser's score that would have won it and asks
    // again rather than quietly picking another.
    await tester.tap(find.bySemanticsLabel('Match to 3'));
    await tester.pumpAndSettle();
    expect(points(4), findsNothing);
    for (final n in [0, 1, 2]) {
      expect(tester.widget<ChoiceChip>(points(n)).selected, isFalse);
    }
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    expect(find.text('Pick the loser\'s points'), findsOneWidget);
    expect(tester.widget<FilledButton>(send).onPressed, isNull);

    // A match to 1 leaves no 0 behind for a longer match.
    await tester.ensureVisible(find.bySemanticsLabel('Match to 1'));
    await tester.tap(find.bySemanticsLabel('Match to 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Match to 3'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(points(0)).selected, isFalse);

    await tester.ensureVisible(points(2));
    await tester.tap(points(2));
    await tester.pumpAndSettle();
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('Match to 3, you lost 2-3'), findsOneWidget);
  });

  testWidgets('a match to 1 needs no loser score', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await tester.pumpWidget(
      AwakeApp(
        repository: repo,
        initialLocation: '/backgammon/record?opponent=demo-2',
      ),
    );
    await tester.pumpAndSettle();

    final send = find.widgetWithText(FilledButton, 'Send for confirmation');
    await tester.ensureVisible(find.bySemanticsLabel('Match to 1'));
    await tester.tap(find.bySemanticsLabel('Match to 1'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(send).onPressed, isNull);

    await tester.ensureVisible(find.text('I won'));
    await tester.tap(find.text('I won'));
    await tester.pumpAndSettle();
    // No choice to make, so no points row.
    expect(find.text('Bogdan\'s points'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '0'), findsNothing);
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('Match to 1, you won 1-0'), findsOneWidget);
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

  testWidgets('the SWU ladder is a route across the starting line', (
    tester,
  ) async {
    _phone(tester);
    final repo = await anaAndBogdanWithSwu();
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Switch game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Star Wars: Unlimited'));
    await tester.pumpAndSettle();

    final route = find.byType(RouteLadder);
    expect(find.text('The route'), findsOneWidget);
    expect(find.text('Bogdan says you lost 0-2'), findsOneWidget);
    // Ana won 2-1 from 1000 each: she's in space, Bogdan below the start.
    expect(
      find.descendant(of: route, matching: find.text('1020')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: route, matching: find.text('980')),
      findsOneWidget,
    );
    expect(find.text('Start 1000'), findsOneWidget);
    expect(find.text('Ground arena'), findsOneWidget);
    expect(find.text('−40'), findsOneWidget);
  });

  testWidgets('a recorded SWU match waits for the opponent', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdan();
    await tester.pumpWidget(
      AwakeApp(
        repository: repo,
        initialLocation: '/swu/record?opponent=demo-2',
      ),
    );
    await tester.pumpAndSettle();

    final send = find.widgetWithText(FilledButton, 'Send for confirmation');
    expect(find.text('2-1'), findsNothing);
    await tester.tap(find.text('I won'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.tap(find.text('2-1'));
    await tester.pumpAndSettle();
    expect(find.text('1000 to '), findsNWidgets(2));
    expect(find.text('+20'), findsOneWidget);

    // A draw is always 1-1, so it's picked for you.
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    expect(find.text('±0'), findsNWidgets(2));

    await tester.tap(find.text('I won'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1-0 on time'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(find.textContaining('Sent to Bogdan'), findsOneWidget);
    expect(find.text('The route'), findsOneWidget);
    expect(find.text('Waiting for Bogdan to confirm'), findsOneWidget);
    expect(find.text('Best of three, you won 1-0'), findsOneWidget);
    expect(repo.me!.swu.rating, swuStartingRating);
  });

  testWidgets('confirming an SWU match rates it', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdanWithSwu();
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/swu'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(repo.me!.swu.rating, lessThan(1020));
    expect(repo.me!.swu.losses, 1);
    expect(
      find.textContaining(
        'Match confirmed. You\'re now ${repo.me!.swu.rating}',
      ),
      findsOneWidget,
    );
    expect(find.text('Bogdan says you lost 0-2'), findsNothing);
  });

  testWidgets('every SWU screen renders at 360px', (tester) async {
    _phone(tester);
    final repo = await anaAndBogdanWithSwu();
    await tester.pumpWidget(
      AwakeApp(repository: repo, initialLocation: '/swu'),
    );
    await tester.pumpAndSettle();

    for (final tab in ['Record', 'History', 'You']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    expect(find.text('Star Wars: Unlimited rating'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Won against Bogdan'),
      200,
      scrollable: _list,
    );

    await tester.tap(find.text('Ladder').last);
    await tester.pumpAndSettle();
    final bogdan = find
        .descendant(
          of: find.byType(RouteLadder),
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

  group('pending result cards', () {
    testWidgets('an incoming chess result previews the confirmer\'s rating', (
      tester,
    ) async {
      _phone(tester);
      final repo = await anaAndBogdan();
      await tester.pumpWidget(AwakeApp(repository: repo));
      await tester.pumpAndSettle();

      // Ana (1020) lost to Bogdan (980) on the board.
      expect(find.text('Bogdan says you lost'), findsOneWidget);
      expect(
        find.textContaining('Confirm and you go to 998 ('),
        findsOneWidget,
      );
      expect(find.text('−22'), findsOneWidget);
      expect(find.text('Reported just now'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(repo.me!.rating, 998, reason: 'the preview matches the server');
    });

    testWidgets('an outgoing chess result previews the reporter\'s rating', (
      tester,
    ) async {
      _phone(tester);
      final repo = await anaAndBogdan();
      await repo.signIn(email: bogdanEmail, password: 'x');
      await tester.pumpWidget(AwakeApp(repository: repo));
      await tester.pumpAndSettle();

      expect(find.text('Waiting for Ana to confirm'), findsOneWidget);
      expect(
        find.textContaining('Once confirmed you go to 1002 ('),
        findsOneWidget,
      );
      expect(find.text('+22'), findsOneWidget);
      expect(find.text('Reported just now'), findsOneWidget);
    });

    testWidgets('an unrated result says ratings stay put', (tester) async {
      _phone(tester);
      final repo = await anaAndBogdan();
      final bogdanId = (await repo.ladder())
          .firstWhere((p) => p.id != repo.me!.id)
          .id;
      await repo.requestMatch(
        opponentId: bogdanId,
        myColor: PieceColor.black,
        myOutcome: Outcome.win,
        clock: const ClockSetting(TimeControl.sudden5),
        rated: false,
      );
      await tester.pumpWidget(AwakeApp(repository: repo));
      await tester.pumpAndSettle();

      expect(find.text('Ratings stay put'), findsOneWidget);
      expect(find.textContaining(' you go to '), findsOneWidget);
      expect(find.text('Waiting for Bogdan to confirm'), findsOneWidget);
    });

    testWidgets('backgammon and SWU cards preview with their own ratings', (
      tester,
    ) async {
      _phone(tester);
      final repo = await anaAndBogdanWithSwu();
      await tester.pumpWidget(AwakeApp(repository: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Switch game'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Backgammon'));
      await tester.pumpAndSettle();
      expect(find.text('Bogdan says you lost 1-3'), findsOneWidget);
      expect(
        find.textContaining('Confirm and you go to 1504 ('),
        findsOneWidget,
      );
      expect(find.text('−18'), findsOneWidget);
      expect(find.text('Reported just now'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(repo.me!.backgammon.rating, 1504);

      await tester.tap(find.byTooltip('Switch game'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Star Wars: Unlimited'));
      await tester.pumpAndSettle();
      expect(find.text('Bogdan says you lost 0-2'), findsOneWidget);
      expect(
        find.textContaining('Confirm and you go to 998 ('),
        findsOneWidget,
      );
      expect(find.text('−22'), findsOneWidget);
      expect(find.text('Reported just now'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(repo.me!.swu.rating, 998);
    });

    testWidgets('declining asks first and can be called off', (tester) async {
      _phone(tester);
      final repo = await anaAndBogdan();
      await tester.pumpWidget(AwakeApp(repository: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
      await tester.pumpAndSettle();
      expect(find.text('Decline Bogdan\'s result?'), findsOneWidget);
      expect(
        find.text('Bogdan will be told, and the result won\'t count.'),
        findsOneWidget,
      );
      expect((await repo.matchRequests()).single.awaits(repo.me!.id), isTrue);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Bogdan says you lost'), findsOneWidget);
      expect((await repo.matchRequests()).single.awaits(repo.me!.id), isTrue);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Decline'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Bogdan says you lost'), findsNothing);
      expect(
        _awaitingBadge('1'),
        findsNothing,
        reason: 'nothing left to answer',
      );
      expect(repo.me!.rating, 1020, reason: 'declined results move no rating');
    });

    testWidgets('the reporter sees the decline until they dismiss it', (
      tester,
    ) async {
      _phone(tester);
      final repo = await anaAndBogdan();
      final request = (await repo.matchRequests()).single;
      await repo.respondToMatchRequest(request.id, accept: false);
      await repo.signIn(email: bogdanEmail, password: 'x');
      await tester.pumpWidget(AwakeApp(repository: repo));
      await tester.pumpAndSettle();

      expect(find.text('Ana declined your game'), findsOneWidget);
      expect(find.textContaining('You had white, you won'), findsOneWidget);
      expect(find.text('Declined just now'), findsOneWidget);
      expect(find.textContaining('Reported'), findsNothing);
      expect(find.textContaining('you go to'), findsNothing);
      expect(find.text('Waiting for Ana to confirm'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Withdraw'), findsNothing);
      expect(
        _awaitingBadge('1'),
        findsNothing,
        reason: 'only incoming pending results are counted',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text('Ana declined your game'), findsNothing);
      expect(await repo.matchRequests(), isEmpty);
    });

    testWidgets('a declined backgammon or SWU match says so too', (
      tester,
    ) async {
      _phone(tester);
      final repo = await anaAndBogdanWithSwu();
      for (final request in await repo.backgammonMatchRequests()) {
        await repo.respondToBackgammonMatchRequest(request.id, accept: false);
      }
      for (final request in await repo.swuMatchRequests()) {
        await repo.respondToSwuMatchRequest(request.id, accept: false);
      }
      await repo.signIn(email: bogdanEmail, password: 'x');
      await tester.pumpWidget(AwakeApp(repository: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Switch game'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Backgammon'));
      await tester.pumpAndSettle();
      expect(find.text('Ana declined your match'), findsOneWidget);
      expect(find.text('Match to 3, you won 3-1'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text('Ana declined your match'), findsNothing);

      await tester.tap(find.byTooltip('Switch game'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Star Wars: Unlimited'));
      await tester.pumpAndSettle();
      expect(find.text('Ana declined your match'), findsOneWidget);
      expect(find.text('Best of three, you won 2-0'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text('Ana declined your match'), findsNothing);
    });

    testWidgets('a card says how long ago it was reported', (tester) async {
      _phone(tester);
      PendingResult card(Duration age) => PendingResult(
        headline: 'Bogdan says you lost',
        detail: 'You had white',
        opponentName: 'Bogdan',
        rated: true,
        incoming: true,
        reportedAt: DateTime.now().subtract(age),
        impact: (after: 984, delta: -16),
        respond: ({required accept}) async => null,
        dismiss: () async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DesignScope(
            spec: roastPawns,
            child: Scaffold(
              body: PendingResultList(
                results: [
                  card(const Duration(hours: 2, minutes: 5)),
                  card(const Duration(minutes: 45)),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Reported 2 h ago'), findsOneWidget);
      expect(find.text('Reported 45 min ago'), findsOneWidget);
      expect(
        find.textContaining('Confirm and you go to 984 ('),
        findsNWidgets(2),
      );
      expect(find.text('−16'), findsNWidgets(2));
    });

    testWidgets('a declined card says when, and nothing about ratings', (
      tester,
    ) async {
      _phone(tester);
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: DesignScope(
            spec: roastPawns,
            child: Scaffold(
              body: PendingResultList(
                results: [
                  PendingResult(
                    headline: 'Ana declined your game',
                    detail: 'You had white, you won',
                    opponentName: 'Ana',
                    rated: false,
                    incoming: false,
                    declined: true,
                    reportedAt: now.subtract(const Duration(hours: 5)),
                    respondedAt: now.subtract(const Duration(hours: 3)),
                    respond: ({required accept}) async => null,
                    dismiss: () async {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Declined 3 h ago'), findsOneWidget);
      expect(find.textContaining('Reported'), findsNothing);
      expect(find.text('Ratings stay put'), findsNothing);
    });
  });

  test('relativeAge counts minutes and hours, then falls back to days', () {
    final now = DateTime(2026, 10, 4, 12, 30);
    String age(Duration ago) => relativeAge(now.subtract(ago), now: now);
    expect(age(const Duration(seconds: 20)), 'just now');
    expect(age(const Duration(minutes: 5)), '5 min ago');
    expect(age(const Duration(hours: 2, minutes: 40)), '2 h ago');
    expect(age(const Duration(hours: 23)), '23 h ago');
    expect(age(const Duration(hours: 30)), 'yesterday');
    expect(age(const Duration(days: 3)), '3 days ago');
    expect(age(const Duration(days: 10)), '24 Sep');
    expect(age(const Duration(minutes: -3)), 'just now');
  });
}

/// A demo ladder whose game history waits on [hold], like a slow connection.
class _CountedGames extends DemoLadderRepository {
  /// How many times a member's own chess games were fetched.
  int ownGamesFetches = 0;

  @override
  Future<List<ChessMatch>> matches({String? playerId, int limit = 50}) {
    if (playerId != null) ownGamesFetches++;
    return super.matches(playerId: playerId, limit: limit);
  }
}
