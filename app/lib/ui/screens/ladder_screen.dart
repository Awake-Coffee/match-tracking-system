import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/ladder_repository.dart';
import '../../domain/models.dart';
import '../app_scope.dart';
import '../game.dart';
import '../ladder/baize_ladder.dart';
import '../ladder/ladder_view.dart';
import '../ladder/pawns_ladder.dart';
import '../ladder/route_ladder.dart';
import '../widgets/load_view.dart';
import '../widgets/match_request_list.dart';

class LadderScreen extends StatelessWidget {
  const LadderScreen({super.key, required this.game});

  final Game game;

  Future<(List<Player>, List<PendingResult>)> _load(
    LadderRepository repo,
  ) async {
    final meId = repo.me!.id;
    return switch (game) {
      Game.chess => await _withPending(
        repo.ladder(),
        repo.matchRequests(),
        (players, r) => PendingResult.chess(repo, meId, r, players),
      ),
      Game.backgammon => await _withPending(
        repo.backgammonLadder(),
        repo.backgammonMatchRequests(),
        (players, r) => PendingResult.backgammon(repo, meId, r, players),
      ),
      Game.swu => await _withPending(
        repo.swuLadder(),
        repo.swuMatchRequests(),
        (players, r) => PendingResult.swu(repo, meId, r, players),
      ),
    };
  }

  /// The ladder and the cards for its pending results, which preview their
  /// rating change against those same players.
  Future<(List<Player>, List<PendingResult>)> _withPending<R>(
    Future<List<Player>> ladder,
    Future<List<R>> requests,
    PendingResult Function(List<Player> players, R request) card,
  ) async {
    final players = await ladder;
    return (players, [for (final r in await requests) card(players, r)]);
  }

  @override
  Widget build(BuildContext context) {
    final meId = context.repo.me?.id;
    return LoadView(
      load: _load,
      builder: (context, data, _) {
        final (players, pending) = data;
        if (players.isEmpty) {
          return MessageView(
            message: 'No one is on the ladder yet.',
            actionLabel: 'Record the first ${game.resultNoun}',
            onAction: () => context.go(game.path('record')),
          );
        }
        final ladder = LadderData(
          game: game,
          players: players,
          meId: meId,
          now: DateTime.now(),
          onOpen: (p) => p.id == meId
              ? context.go(game.path('me'))
              : context.push(game.path('players/${p.id}')),
        );
        return ListView(
          children: [
            PendingResultList(results: pending),
            switch (game) {
              Game.chess => PawnsLadder(data: ladder),
              Game.backgammon => BaizeLadder(data: ladder),
              Game.swu => RouteLadder(data: ladder),
            },
          ],
        );
      },
    );
  }
}
