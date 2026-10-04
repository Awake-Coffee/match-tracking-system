import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/domain/models.dart';

const anaEmail = 'ana@example.com';
const bogdanEmail = 'bogdan@example.com';

/// Ana and Bogdan with one rated game (Ana won) and one Bogdan reported
/// against Ana that waits for her to confirm. Signed in as Ana.
Future<DemoLadderRepository> anaAndBogdan() async {
  final repo = DemoLadderRepository();
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
