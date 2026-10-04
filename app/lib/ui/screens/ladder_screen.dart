import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/ladder_repository.dart';
import '../../domain/models.dart';
import '../app_scope.dart';
import '../game.dart';
import '../ladder/baize_ladder.dart';
import '../ladder/ladder_view.dart';
import '../ladder/pawns_ladder.dart';
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
      Game.chess => (
        await repo.ladder(),
        [
          for (final r in await repo.matchRequests())
            PendingResult.chess(repo, meId, r),
        ],
      ),
      Game.backgammon => (
        await repo.backgammonLadder(),
        [
          for (final r in await repo.backgammonMatchRequests())
            PendingResult.backgammon(repo, meId, r),
        ],
      ),
    };
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
            },
          ],
        );
      },
    );
  }
}
