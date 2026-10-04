import 'package:awake_ladder/app.dart';
import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:awake_ladder/ui/screens/history_screen.dart';
import 'package:awake_ladder/ui/widgets/match_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ladder_fixture.dart';

/// A viewport tall enough to build every tile of a full page and one more
/// (the list builds only what is on screen).
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 12000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<String> _idOf(DemoLadderRepository repo, String name) async =>
    (await repo.ladder()).firstWhere((p) => p.displayName == name).id;

/// [reporter] reports a game against [opponent] that [opponent] confirms,
/// then signs back in as [backTo].
Future<void> _play(
  DemoLadderRepository repo, {
  required String reporter,
  required String reporterEmail,
  required String opponent,
  required String opponentEmail,
  required Outcome outcome,
  required String backTo,
}) async {
  final opponentId = await _idOf(repo, opponent);
  await repo.signIn(email: reporterEmail, password: 'x');
  final request = await repo.requestMatch(
    opponentId: opponentId,
    myColor: PieceColor.white,
    myOutcome: outcome,
    clock: const ClockSetting(TimeControl.sudden5),
  );
  await repo.signIn(email: opponentEmail, password: 'x');
  await repo.respondToMatchRequest(request.id, accept: true);
  await repo.signIn(email: backTo, password: 'x');
}

/// Ana and Bogdan's confirmed game (Ana won) plus [draws] more between them,
/// all draws so the first game is the only "Ana beat Bogdan". Signed in as Ana.
Future<DemoLadderRepository> _withDraws(int draws) async {
  final repo = await anaAndBogdan();
  for (var i = 0; i < draws; i++) {
    await _play(
      repo,
      reporter: 'Ana',
      reporterEmail: anaEmail,
      opponent: 'Bogdan',
      opponentEmail: bogdanEmail,
      outcome: Outcome.draw,
      backTo: anaEmail,
    );
  }
  return repo;
}

/// [_withDraws] for a page of draws, with Bogdan beating Cleo once before
/// them and once after: Ana's games fill more than a page and Cleo's sit on
/// either side. Signed in as Ana.
Future<DemoLadderRepository> _anaPagesAndCleo() async {
  final repo = await anaAndBogdan();
  await repo.signUp(
    email: 'cleo@example.com',
    password: 'x',
    displayName: 'Cleo',
  );
  await repo.signIn(email: anaEmail, password: 'x');
  Future<void> bogdanBeatsCleo() => _play(
    repo,
    reporter: 'Bogdan',
    reporterEmail: bogdanEmail,
    opponent: 'Cleo',
    opponentEmail: 'cleo@example.com',
    outcome: Outcome.win,
    backTo: anaEmail,
  );
  await bogdanBeatsCleo();
  for (var i = 0; i < HistoryScreen.pageSize; i++) {
    await _play(
      repo,
      reporter: 'Ana',
      reporterEmail: anaEmail,
      opponent: 'Bogdan',
      opponentEmail: bogdanEmail,
      outcome: Outcome.draw,
      backTo: anaEmail,
    );
  }
  await bogdanBeatsCleo();
  return repo;
}

Future<void> _pick(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownMenu<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

/// What the Player dropdown says.
String _filterText(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byType(DropdownMenu<String>),
        matching: find.byType(TextField),
      ),
    )
    .controller!
    .text;

Future<void> _openHistory(
  WidgetTester tester,
  DemoLadderRepository repo,
) async {
  await tester.pumpWidget(AwakeApp(repository: repo));
  await tester.pumpAndSettle();
  await tester.tap(find.text('History').last);
  await tester.pumpAndSettle();
}

const underline = TextDecoration.underline;

/// The bold span that holds [name] in a result's sentence.
TextSpan _nameSpan(WidgetTester tester, String name) {
  TextSpan? found;
  for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
    text.text.visitChildren((span) {
      if (span is TextSpan && span.text == name && span.children == null) {
        found = span;
      }
      return found == null;
    });
    if (found != null) break;
  }
  return found!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a name in the club history opens that player', (tester) async {
    _tall(tester);
    final repo = await anaAndBogdan();
    await _openHistory(tester, repo);

    final sentence = find.text('Ana beat Bogdan', findRichText: true);
    expect(sentence, findsOneWidget);
    await tester.tapOnText(find.textRange.ofSubstring('Bogdan'));
    await tester.pumpAndSettle();

    expect(find.text('Rating over time'), findsOneWidget);
    expect(
      find.text('Every game played at Awake, newest first.'),
      findsNothing,
    );
    expect(find.text('Bogdan'), findsWidgets);
  });

  testWidgets('a deleted member stays in the history without a link', (
    tester,
  ) async {
    _tall(tester);
    final repo = await anaAndBogdan();
    await repo.deleteAccount();
    await repo.signIn(email: bogdanEmail, password: 'x');

    // The club history: Ana is plain bold, Bogdan still a link.
    await _openHistory(tester, repo);
    expect(find.text('Ana beat Bogdan', findRichText: true), findsOneWidget);
    expect(_nameSpan(tester, 'Ana').recognizer, isNull);
    expect(_nameSpan(tester, 'Ana').style!.decoration, isNot(underline));
    expect(_nameSpan(tester, 'Bogdan').style!.decoration, underline);

    // Bogdan's own results: the row against Ana opens nothing.
    await tester.tapOnText(find.textRange.ofSubstring('Bogdan'));
    await tester.pumpAndSettle();
    final row = find.text('Lost to Ana', findRichText: true);
    expect(row, findsOneWidget);
    final tile = find.ancestor(of: row, matching: find.byType(InkWell)).first;
    expect(tester.widget<InkWell>(tile).onTap, isNull);
    expect(_nameSpan(tester, 'Ana').style!.decoration, isNot(underline));
  });

  testWidgets('a name in the backgammon history opens that player', (
    tester,
  ) async {
    _tall(tester);
    final repo = await anaAndBogdanWithBackgammon();
    await tester.pumpWidget(AwakeApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(switchGame);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backgammon'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History').last);
    await tester.pumpAndSettle();

    await tester.tapOnText(find.textRange.ofSubstring('Bogdan'));
    await tester.pumpAndSettle();

    expect(find.text('Backgammon rating'), findsOneWidget);
    expect(find.text('Bogdan'), findsWidgets);
  });

  testWidgets('the filter shows one member\'s games', (tester) async {
    _tall(tester);
    final repo = await anaAndBogdan();
    await repo.signUp(
      email: 'cleo@example.com',
      password: 'x',
      displayName: 'Cleo',
    );
    await repo.signOut();
    // Ana beat Bogdan; Bogdan beat Cleo.
    await _play(
      repo,
      reporter: 'Bogdan',
      reporterEmail: bogdanEmail,
      opponent: 'Cleo',
      opponentEmail: 'cleo@example.com',
      outcome: Outcome.win,
      backTo: anaEmail,
    );
    await _openHistory(tester, repo);

    expect(find.byType(MatchTile), findsNWidgets(2));
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cleo').last);
    await tester.pumpAndSettle();

    expect(find.byType(MatchTile), findsOneWidget);
    expect(find.text('Bogdan beat Cleo', findRichText: true), findsOneWidget);

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Everyone').last);
    await tester.pumpAndSettle();
    expect(find.byType(MatchTile), findsNWidgets(2));
  });

  testWidgets('a member with no games says so', (tester) async {
    _tall(tester);
    final repo = await anaAndBogdan();
    await repo.signUp(
      email: 'cleo@example.com',
      password: 'x',
      displayName: 'Cleo',
    );
    await repo.signIn(email: anaEmail, password: 'x');
    await _openHistory(tester, repo);

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cleo').last);
    await tester.pumpAndSettle();

    expect(find.text('No games for this player yet.'), findsOneWidget);
    expect(find.text('Record the first game'), findsNothing);
  });

  testWidgets('Load more appends the next page until none remain', (
    tester,
  ) async {
    _tall(tester);
    // One more than a page, so the first game falls on page two.
    final repo = await _withDraws(HistoryScreen.pageSize);
    await _openHistory(tester, repo);

    expect(find.byType(MatchTile), findsNWidgets(HistoryScreen.pageSize));
    expect(find.text('Ana beat Bogdan', findRichText: true), findsNothing);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(find.byType(MatchTile), findsNWidgets(HistoryScreen.pageSize + 1));
    expect(find.text('Ana beat Bogdan', findRichText: true), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('a history of exactly one page has no Load more', (tester) async {
    _tall(tester);
    final repo = await _withDraws(HistoryScreen.pageSize - 1);
    await _openHistory(tester, repo);

    expect(find.byType(MatchTile), findsNWidgets(HistoryScreen.pageSize));
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('Load more keeps the player filter', (tester) async {
    _tall(tester);
    final repo = await _anaPagesAndCleo();
    await _openHistory(tester, repo);
    await _pick(tester, 'Ana');

    expect(find.byType(MatchTile), findsNWidgets(HistoryScreen.pageSize));
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(find.byType(MatchTile), findsNWidgets(HistoryScreen.pageSize + 1));
    expect(find.text('Ana beat Bogdan', findRichText: true), findsOneWidget);
    expect(find.text('Bogdan beat Cleo', findRichText: true), findsNothing);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('pages loaded with Load more survive a background reload', (
    tester,
  ) async {
    _tall(tester);
    final repo = await _withDraws(HistoryScreen.pageSize);
    await _openHistory(tester, repo);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    repo.reload();
    await tester.pumpAndSettle();

    expect(find.byType(MatchTile), findsNWidgets(HistoryScreen.pageSize + 1));
    expect(find.text('Ana beat Bogdan', findRichText: true), findsOneWidget);
  });

  testWidgets('a new filter starts again from its first page', (tester) async {
    _tall(tester);
    final repo = await _anaPagesAndCleo();
    await _openHistory(tester, repo);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.byType(MatchTile), findsNWidgets(HistoryScreen.pageSize + 3));

    await _pick(tester, 'Ana');

    expect(find.byType(MatchTile), findsNWidgets(HistoryScreen.pageSize));
    expect(find.text('Bogdan beat Cleo', findRichText: true), findsNothing);
    expect(find.text('Load more'), findsOneWidget);
  });

  testWidgets('a filter that fails to load goes back to what is shown', (
    tester,
  ) async {
    _tall(tester);
    final repo = SharedLadder();
    await anaAndBogdan(into: repo);
    await _openHistory(tester, repo);
    expect(find.byType(MatchTile), findsOneWidget);

    repo.offline = true;
    await _pick(tester, 'Bogdan');

    expect(find.textContaining('Couldn\'t show that player'), findsOneWidget);
    expect(_filterText(tester), 'Everyone');
    expect(find.byType(MatchTile), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    repo.offline = false;
    await _pick(tester, 'Bogdan');
    expect(_filterText(tester), 'Bogdan');
    expect(find.byType(MatchTile), findsOneWidget);
  });

  group('the before cursor', () {
    test('returns only results played before it', () async {
      final repo = await _withDraws(2);
      final all = await repo.matches();
      expect(all, hasLength(3));

      final older = await repo.matches(before: all.first.playedAt);
      expect(older.map((m) => m.id), all.skip(1).map((m) => m.id));
      expect(await repo.matches(before: all.last.playedAt), isEmpty);
    });

    test('works with a player and a limit', () async {
      final repo = await _withDraws(3);
      final anaId = repo.me!.id;
      final all = await repo.matches(playerId: anaId);
      final page = await repo.matches(
        playerId: anaId,
        limit: 2,
        before: all.first.playedAt,
      );
      expect(page.map((m) => m.id), all.skip(1).take(2).map((m) => m.id));
    });

    test('pages backgammon and Star Wars: Unlimited too', () async {
      final repo = await anaAndBogdanWithSwu();
      final backgammon = (await repo.backgammonMatches()).single;
      final swu = (await repo.swuMatches()).single;

      expect(
        await repo.backgammonMatches(before: DateTime.now()),
        hasLength(1),
      );
      expect(
        await repo.backgammonMatches(before: backgammon.playedAt),
        isEmpty,
      );
      expect(await repo.swuMatches(before: DateTime.now()), hasLength(1));
      expect(await repo.swuMatches(before: swu.playedAt), isEmpty);
    });
  });
}
