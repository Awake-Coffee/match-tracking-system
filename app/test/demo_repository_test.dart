import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/data/ladder_repository.dart';
import 'package:awake_ladder/domain/elo.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seeded ladder is zero-sum and replays from history', () async {
    final repo = DemoLadderRepository();
    final players = await repo.ladder();
    final total = players.fold<int>(0, (s, p) => s + p.rating);
    expect(total, startingRating * players.length);

    for (final p in players) {
      final games = await repo.matches(playerId: p.id, limit: 1000);
      expect(games.length, p.gamesPlayed);
      expect(p.wins + p.losses + p.draws, p.gamesPlayed);
      final history = ratingHistory(p.id, games.reversed.toList());
      expect(history.first, startingRating);
      expect(history.last, p.rating);
    }
  });

  test('ladder is sorted by rating, then games, then name', () async {
    final players = await DemoLadderRepository().ladder();
    for (var i = 1; i < players.length; i++) {
      expect(compareLadder(players[i - 1], players[i]), lessThanOrEqualTo(0));
    }
  });

  test('new members start at 1000 and recording updates both players', () async {
    final repo = DemoLadderRepository(seed: false);
    await repo.signUp(email: 'bo@example.com', password: 'password', displayName: 'Bo');
    final bo = repo.me!;
    await repo.signOut();
    await repo.signUp(email: 'ana@example.com', password: 'password', displayName: 'Ana');
    expect(repo.me!.rating, 1000);

    final revision = repo.revision;
    final match = await repo.recordMatch(
      opponentId: bo.id,
      myColor: PieceColor.black,
      myOutcome: Outcome.win,
    );
    expect(match.result, MatchResult.black);
    expect(match.deltaFor(repo.me!.id), 16);
    expect(repo.me!.rating, 1016);
    expect((await repo.player(bo.id)).rating, 984);
    expect(repo.revision, greaterThan(revision));
  });

  test('rejects playing yourself and duplicate names', () async {
    final repo = DemoLadderRepository(seed: false);
    await repo.signUp(email: 'a@example.com', password: 'password', displayName: 'Ana');
    final me = repo.me!;
    await expectLater(
      repo.recordMatch(opponentId: me.id, myColor: PieceColor.white, myOutcome: Outcome.win),
      throwsA(isA<LadderException>()),
    );
    await repo.signOut();
    await repo.signUp(email: 'b@example.com', password: 'password', displayName: 'ana');
    expect(repo.me!.displayName, 'ana 2');
    await expectLater(repo.updateProfile(displayName: 'ANA'), throwsA(isA<LadderException>()));
  });
}
