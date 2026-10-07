import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/data/ladder_repository.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const anaEmail = 'ana@example.com';
const bogdanEmail = 'bogdan@example.com';

/// The header's game picker. Its tooltip names the game in full on phones,
/// where the header shows only the short name, so match on the prefix.
final switchGame = find.byTooltip(RegExp(r'^Switch game'));

/// A mode's name on the ladders overview. Chess sets it in capitals, like
/// every line on its board; the other games as written.
Finder modeLine(String label) => find.byWidgetPredicate(
  (w) => w is Text && (w.data == label || w.data == label.toUpperCase()),
  description: 'mode line "$label"',
);

/// A demo ladder that behaves like a backend shared with other devices:
/// changes can land there without this client hearing of them, and the
/// connection can drop.
class SharedLadder extends DemoLadderRepository {
  bool _away = false;
  int _heard = 0;

  /// While true, loading the ladder fails as on a dropped request.
  bool offline = false;

  /// What this client has heard of: the revision moves only when it is told.
  @override
  int get revision => _heard;

  @override
  void notifyListeners() {
    if (_away) return;
    _heard = super.revision;
    super.notifyListeners();
  }

  /// Runs [change] as if on another member's device: the data changes but
  /// this client isn't told until something reloads it.
  Future<void> elsewhere(Future<void> Function() change) async {
    _away = true;
    try {
      await change();
    } finally {
      _away = false;
    }
  }

  @override
  Future<List<Player>> members() async {
    if (offline) throw Exception('connection dropped');
    return super.members();
  }
}

/// The duels most tests report, from the signed-in member's side (white is
/// side 1 in chess, the reporter otherwise), and reads per game.
extension Duels on LadderRepository {
  Future<ResultRequest> reportChess({
    required String opponentId,
    required PieceColor myColor,
    required Outcome myOutcome,
    required ClockSetting clock,
    bool rated = true,
    GameMode mode = GameMode.standardChess,
  }) {
    final mySide = myColor == PieceColor.white ? 1 : 2;
    return reportResult(
      ResultReport(
        mode: mode,
        seats: [
          (playerId: me!.id, side: mySide, score: myOutcome.score),
          (playerId: opponentId, side: 3 - mySide, score: 1 - myOutcome.score),
        ],
        rated: rated,
        clock: clock,
      ),
    );
  }

  Future<ResultRequest> reportBackgammon({
    required String opponentId,
    required int myScore,
    required int opponentScore,
    bool rated = true,
    GameMode mode = GameMode.standardBackgammon,
  }) => _reportDuel(mode, opponentId, myScore, opponentScore, rated);

  Future<ResultRequest> reportSwu({
    required String opponentId,
    required int myGames,
    required int opponentGames,
    bool rated = true,
    GameMode mode = GameMode.premier,
    int bestOf = 3,
  }) => _reportDuel(
    mode,
    opponentId,
    myGames,
    opponentGames,
    rated,
    bestOf: bestOf,
  );

  Future<ResultRequest> _reportDuel(
    GameMode mode,
    String opponentId,
    int myScore,
    int opponentScore,
    bool rated, {
    int? bestOf,
  }) => reportResult(
    ResultReport(
      mode: mode,
      seats: [
        (playerId: me!.id, side: 1, score: myScore),
        (playerId: opponentId, side: 2, score: opponentScore),
      ],
      rated: rated,
      bestOf: bestOf,
    ),
  );

  /// Every member in [mode]'s ladder order.
  Future<List<Player>> ladderIn(GameMode mode) async =>
      ladderOf(await members(), mode);

  /// The signed-in member's open and declined requests in [type].
  Future<List<ResultRequest>> requestsIn(MatchType type) async => [
    for (final r in await requests())
      if (r.mode.type == type) r,
  ];
}

/// A member's standing in each game's original mode.
extension OriginalModes on Player {
  Standing get chess => standingIn(GameMode.standardChess);
  Standing get backgammon => standingIn(GameMode.standardBackgammon);
  Standing get swu => standingIn(GameMode.premier);
}

/// Ana and Bogdan with one rated game (Ana won) and one Bogdan reported
/// against Ana that waits for her to confirm. Signed in as Ana. Fills [into]
/// when given.
Future<DemoLadderRepository> anaAndBogdan({DemoLadderRepository? into}) async {
  final repo = into ?? DemoLadderRepository();
  await repo.signUp(email: anaEmail, password: 'x', displayName: 'Ana');
  final anaId = repo.me!.id;
  await repo.signOut();
  await repo.signUp(email: bogdanEmail, password: 'x', displayName: 'Bogdan');
  final bogdanId = repo.me!.id;
  await repo.signOut();

  await repo.signIn(email: anaEmail, password: 'x');
  final rated = await repo.reportChess(
    opponentId: bogdanId,
    myColor: PieceColor.white,
    myOutcome: Outcome.win,
    clock: const ClockSetting(TimeControl.sudden5),
  );
  await repo.signIn(email: bogdanEmail, password: 'x');
  await repo.respondToRequest(rated.id, accept: true);
  await repo.reportChess(
    opponentId: anaId,
    myColor: PieceColor.white,
    myOutcome: Outcome.win,
    clock: const ClockSetting(TimeControl.fischer5plus3),
  );
  await repo.signIn(email: anaEmail, password: 'x');
  return repo;
}

/// [anaAndBogdan] plus backgammon: one rated match to 5 (Ana won 5-3) and
/// one to 3 Bogdan reported winning 3-1 that waits for Ana. Signed in as Ana.
Future<DemoLadderRepository> anaAndBogdanWithBackgammon() async {
  final repo = await anaAndBogdan();
  final anaId = repo.me!.id;
  final bogdanId = (await repo.ladderIn(GameMode.standardChess))
      .firstWhere((p) => p.id != anaId)
      .id;

  final rated = await repo.reportBackgammon(
    opponentId: bogdanId,
    myScore: 5,
    opponentScore: 3,
  );
  await repo.signIn(email: bogdanEmail, password: 'x');
  await repo.respondToRequest(rated.id, accept: true);
  await repo.reportBackgammon(opponentId: anaId, myScore: 3, opponentScore: 1);
  await repo.signIn(email: anaEmail, password: 'x');
  return repo;
}

/// [anaAndBogdanWithBackgammon] plus Star Wars: Unlimited: one rated match
/// (Ana won 2-1) and one Bogdan reported winning 2-0 that waits for Ana.
/// Signed in as Ana.
Future<DemoLadderRepository> anaAndBogdanWithSwu() async {
  final repo = await anaAndBogdanWithBackgammon();
  final anaId = repo.me!.id;
  final bogdanId = (await repo.ladderIn(GameMode.standardChess))
      .firstWhere((p) => p.id != anaId)
      .id;

  final rated = await repo.reportSwu(
    opponentId: bogdanId,
    myGames: 2,
    opponentGames: 1,
  );
  await repo.signIn(email: bogdanEmail, password: 'x');
  await repo.respondToRequest(rated.id, accept: true);
  await repo.reportSwu(opponentId: anaId, myGames: 2, opponentGames: 0);
  await repo.signIn(email: anaEmail, password: 'x');
  return repo;
}
