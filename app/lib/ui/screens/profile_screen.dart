import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../widgets/load_view.dart';
import '../widgets/match_tile.dart';
import '../widgets/rating_chart.dart';
import '../widgets/surface.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.playerId, required this.isMe});

  final String playerId;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return LoadView<(Player, List<ChessMatch>)>(
      load: (repo) async => (
        await repo.player(playerId),
        await repo.matches(playerId: playerId, limit: 500),
      ),
      builder: (context, data, _) => _Profile(player: data.$1, matches: data.$2, isMe: isMe),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile({required this.player, required this.matches, required this.isMe});

  final Player player;

  /// Newest first.
  final List<ChessMatch> matches;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final p = player;
    final oldestFirst = matches.reversed.toList();
    final history = ratingHistory(p.id, oldestFirst);
    final peak = history.reduce(math.max);
    final section = d.display(22);

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.displayName, style: d.display(36)),
                    if (isMe) Text('Your profile', style: d.body(15, color: d.muted)),
                  ],
                ),
              ),
              if (isMe)
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.push('/settings'),
                )
              else if (context.canPop())
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.close),
                  onPressed: () => context.pop(),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: SpecSurface(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rating', style: d.body(14, color: d.muted, weight: FontWeight.w600)),
                Text('${p.rating}', style: d.display(64, height: 1.05)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    _Stat(label: 'Games', value: '${p.gamesPlayed}'),
                    _Stat(label: 'Won', value: '${p.wins}'),
                    _Stat(label: 'Lost', value: '${p.losses}'),
                    _Stat(label: 'Drawn', value: '${p.draws}'),
                    _Stat(label: 'Peak', value: '$peak'),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (!isMe)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: OutlinedButton(
              onPressed: () => context.go('/record?opponent=${p.id}'),
              child: Text('Record a game with ${p.displayName}'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
          child: Text('Rating over time', style: section),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: history.length < 2
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    isMe
                        ? 'Your line starts after your first game.'
                        : '${p.displayName} hasn\'t played yet.',
                    style: d.body(15, color: d.muted),
                  ),
                )
              : RatingChart(
                  points: history,
                  describe: (i) {
                    if (i == 0) return 'Start: ${history[0]}';
                    final m = oldestFirst[i - 1];
                    final verb = switch (m.outcomeFor(p.id)) {
                      Outcome.win => 'Beat',
                      Outcome.loss => 'Lost to',
                      Outcome.draw => 'Drew with',
                    };
                    return 'Game $i: $verb ${m.opponentName(p.id)}\n'
                        '${history[i]} (${formatDelta(m.deltaFor(p.id))})';
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 4),
          child: Text('Recent games', style: section),
        ),
        if (matches.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('No games yet.', style: d.body(15, color: d.muted)),
          ),
        for (final (i, m) in matches.take(20).indexed) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: SpecRule(verticalPadding: 0),
            ),
          MatchTile(match: m, perspectiveId: p.id),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: d.number(20, weight: FontWeight.w700)),
        Text(label, style: d.body(13, color: d.muted)),
      ],
    );
  }
}
