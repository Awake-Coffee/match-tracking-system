import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../game.dart';
import '../widgets/load_view.dart';
import '../widgets/match_tile.dart';
import '../widgets/surface.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final noun = game.resultNoun;
    return LoadView<List<Widget>>(
      load: (repo) async => switch (game) {
        Game.chess => [
          for (final m in await repo.matches(limit: 100)) MatchTile(match: m),
        ],
        Game.backgammon => [
          for (final m in await repo.backgammonMatches(limit: 100))
            BackgammonMatchTile(match: m),
        ],
        Game.swu => [
          for (final m in await repo.swuMatches(limit: 100))
            SwuMatchTile(match: m),
        ],
      },
      builder: (context, tiles, _) => ListView(
        children: [
          ScreenTitle(
            'History',
            subtitle: switch (game) {
              Game.chess => 'Every game played at Awake, newest first.',
              Game.backgammon =>
                'Every backgammon match at Awake, newest first.',
              Game.swu =>
                'Every Star Wars: Unlimited match at Awake, newest first.',
            },
          ),
          if (tiles.isEmpty)
            MessageView(
              message: 'No ${game.resultNounPlural} yet.',
              actionLabel: 'Record the first $noun',
              onAction: () => context.go(game.path('record')),
            ),
          for (final (i, tile) in tiles.indexed) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: SpecRule(verticalPadding: 0),
              ),
            tile,
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
