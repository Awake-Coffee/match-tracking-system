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
