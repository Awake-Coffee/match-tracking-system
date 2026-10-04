import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

const anaEmail = 'ana@example.com';
const bogdanEmail = 'bogdan@example.com';

/// The header's game picker. Its tooltip names the game in full on phones,
/// where the header shows only the short name, so match on the prefix.
final switchGame = find.byTooltip(RegExp(r'^Switch game'));

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
  Future<List<Player>> ladder() async {
    if (offline) throw Exception('connection dropped');
    return super.ladder();
  }
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
  final rated = await repo.requestMatch(
    opponentId: bogdanId,
    myColor: PieceColor.white,
    myOutcome: Outcome.win,
    clock: const ClockSetting(TimeControl.sudden5),
  );
  await repo.signIn(email: bogdanEmail, password: 'x');
  await repo.respondToMatchRequest(rated.id, accept: true);
  await repo.requestMatch(
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
  final bogdanId = (await repo.ladder()).firstWhere((p) => p.id != anaId).id;

  final rated = await repo.requestBackgammonMatch(
    opponentId: bogdanId,
    matchLength: 5,
    myScore: 5,
    opponentScore: 3,
  );
  await repo.signIn(email: bogdanEmail, password: 'x');
  await repo.respondToBackgammonMatchRequest(rated.id, accept: true);
  await repo.requestBackgammonMatch(
    opponentId: anaId,
    matchLength: 3,
    myScore: 3,
    opponentScore: 1,
  );
  await repo.signIn(email: anaEmail, password: 'x');
  return repo;
}

/// [anaAndBogdanWithBackgammon] plus Star Wars: Unlimited: one rated match
/// (Ana won 2-1) and one Bogdan reported winning 2-0 that waits for Ana.
/// Signed in as Ana.
Future<DemoLadderRepository> anaAndBogdanWithSwu() async {
  final repo = await anaAndBogdanWithBackgammon();
  final anaId = repo.me!.id;
  final bogdanId = (await repo.ladder()).firstWhere((p) => p.id != anaId).id;

  final rated = await repo.requestSwuMatch(
    opponentId: bogdanId,
    myGames: 2,
    opponentGames: 1,
  );
  await repo.signIn(email: bogdanEmail, password: 'x');
  await repo.respondToSwuMatchRequest(rated.id, accept: true);
  await repo.requestSwuMatch(opponentId: anaId, myGames: 2, opponentGames: 0);
  await repo.signIn(email: anaEmail, password: 'x');
  return repo;
}
