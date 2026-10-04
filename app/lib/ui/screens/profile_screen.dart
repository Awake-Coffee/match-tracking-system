import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../domain/backgammon.dart';
import '../../domain/models.dart';
import '../../domain/swu.dart';
import '../game.dart';
import '../ladder/ladder_view.dart';
import '../widgets/load_view.dart';
import '../widgets/match_tile.dart';
import '../widgets/rating_chart.dart';
import '../widgets/surface.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.game,
    required this.playerId,
    required this.isMe,
  });

  final Game game;
  final String playerId;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return LoadView<_GameRecord>(
      load: (repo) async {
        final player = await repo.player(playerId);
        // Opponents who deleted their account stay in the results unlinked.
        final memberIds = {for (final p in await repo.ladder()) p.id};
        final chase = isMe ? await _chase(repo) : null;
        return switch (game) {
          Game.chess => _GameRecord.chess(
            player,
            await repo.matches(playerId: playerId, limit: 500),
            memberIds,
            chase,
          ),
          Game.backgammon => _GameRecord.backgammon(
            player,
            await repo.backgammonMatches(playerId: playerId, limit: 500),
            memberIds,
            chase,
          ),
          Game.swu => _GameRecord.swu(
            player,
            await repo.swuMatches(playerId: playerId, limit: 500),
            memberIds,
            chase,
          ),
        };
      },
      builder: (context, record, _) =>
          _Profile(game: game, record: record, isMe: isMe),
    );
  }

  /// How far the next rung up is for this member, from the same ladder the
  /// ladder screen ranks by.
  Future<String?> _chase(LadderRepository repo) async => LadderData(
    game: game,
    players: await game.ladderOf(repo),
    meId: playerId,
    onOpen: (_) {},
    now: DateTime.now(),
  ).chase;
}

/// A player's standing and results in one game, ready to show.
class _GameRecord {
  _GameRecord({
    required this.player,
    required this.rating,
    required this.stats,
    required this.history,
    required this.describePoint,
    required this.tiles,
    this.chase,
  });

  /// [matches] newest first; only rated ones are on the rating line.
  /// [memberIds] are the members who still have a profile to link to.
  factory _GameRecord.chess(
    Player p,
    List<ChessMatch> matches,
    Set<String> memberIds,
    String? chase,
  ) {
    final oldestFirst = matches.reversed.where((m) => m.rated).toList();
    final history = ratingHistory(p.id, oldestFirst);
    return _GameRecord(
      player: p,
      chase: chase,
      rating: p.rating,
      stats: [
        ('Games', p.gamesPlayed),
        ('Won', p.wins),
        ('Lost', p.losses),
        ('Drawn', p.draws),
        ('Peak', p.peakRating),
      ],
      history: history,
      describePoint: (i) {
        final m = oldestFirst[i - 1];
        final verb = switch (m.outcomeFor(p.id)) {
          Outcome.win => 'Beat',
          Outcome.loss => 'Lost to',
          Outcome.draw => 'Drew with',
        };
        return 'Game $i: $verb ${m.opponentName(p.id)}\n'
            '${history[i]} (${formatDelta(m.deltaFor(p.id))})';
      },
      tiles: [
        for (final m in matches.take(20))
          MatchTile(match: m, memberIds: memberIds, perspectiveId: p.id),
      ],
    );
  }

  /// [matches] newest first; only rated ones are on the rating line.
  factory _GameRecord.backgammon(
    Player p,
    List<BackgammonMatch> matches,
    Set<String> memberIds,
    String? chase,
  ) {
    final oldestFirst = matches.reversed.where((m) => m.rated).toList();
    final history = ratingHistory(
      p.id,
      oldestFirst,
      start: backgammonStartingRating,
    );
    final bg = p.backgammon;
    return _GameRecord(
      player: p,
      chase: chase,
      rating: bg.rating,
      stats: [
        ('Matches', bg.matchesPlayed),
        ('Won', bg.wins),
        ('Lost', bg.losses),
        ('Peak', bg.peakRating),
      ],
      history: history,
      describePoint: (i) {
        final m = oldestFirst[i - 1];
        return 'Match $i: ${m.wonBy(p.id) ? 'Beat' : 'Lost to'} '
            '${m.opponentName(p.id)} ${m.scoreFor(p.id)}\n'
            '${history[i]} (${formatDelta(m.deltaFor(p.id))})';
      },
      tiles: [
        for (final m in matches.take(20))
          BackgammonMatchTile(
            match: m,
            memberIds: memberIds,
            perspectiveId: p.id,
          ),
      ],
    );
  }

  /// [matches] newest first; only rated ones are on the rating line.
  factory _GameRecord.swu(
    Player p,
    List<SwuMatch> matches,
    Set<String> memberIds,
    String? chase,
  ) {
    final oldestFirst = matches.reversed.where((m) => m.rated).toList();
    final history = ratingHistory(p.id, oldestFirst, start: swuStartingRating);
    final swu = p.swu;
    return _GameRecord(
      player: p,
      chase: chase,
      rating: swu.rating,
      stats: [
        ('Matches', swu.matchesPlayed),
        ('Won', swu.wins),
        ('Lost', swu.losses),
        ('Drawn', swu.draws),
        ('Peak', swu.peakRating),
      ],
      history: history,
      describePoint: (i) {
        final m = oldestFirst[i - 1];
        final verb = switch (m.outcomeFor(p.id)) {
          Outcome.win => 'Beat',
          Outcome.loss => 'Lost to',
          Outcome.draw => 'Drew with',
        };
        return 'Match $i: $verb ${m.opponentName(p.id)} ${m.scoreFor(p.id)}\n'
            '${history[i]} (${formatDelta(m.deltaFor(p.id))})';
      },
      tiles: [
        for (final m in matches.take(20))
          SwuMatchTile(match: m, memberIds: memberIds, perspectiveId: p.id),
      ],
    );
  }

  final Player player;
  final int rating;
  final List<(String, int)> stats;

  /// Rating at the start and after each result, oldest first.
  final List<int> history;

  /// Chart tooltip for history point i ≥ 1.
  final String Function(int i) describePoint;

  /// The 20 most recent results, newest first.
  final List<Widget> tiles;

  /// "10 to pass Irina", shown under the rating; null when nobody is above.
  final String? chase;
}

class _Profile extends StatelessWidget {
  const _Profile({
    required this.game,
    required this.record,
    required this.isMe,
  });

  final Game game;
  final _GameRecord record;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final p = record.player;
    final history = record.history;
    final noun = game.resultNoun;
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
                    if (isMe)
                      Text('Your profile', style: d.body(15, color: d.muted)),
                  ],
                ),
              ),
              if (isMe)
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.push(game.path('settings')),
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
                Text(
                  '${game.label} rating',
                  style: d.body(14, color: d.muted, weight: FontWeight.w600),
                ),
                Text('${record.rating}', style: d.display(64, height: 1.05)),
                if (record.chase case final chase?)
                  Text(
                    chase,
                    style: d.body(15, color: d.accent, weight: FontWeight.w700),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    for (final (label, value) in record.stats)
                      _Stat(label: label, value: '$value'),
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
              onPressed: () => context.go(game.path('record?opponent=${p.id}')),
              child: Text('Record a $noun with ${p.displayName}'),
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
                        ? 'Your line starts after your first $noun.'
                        : '${p.displayName} hasn\'t played yet.',
                    style: d.body(15, color: d.muted),
                  ),
                )
              : RatingChart(
                  points: history,
                  describe: (i) =>
                      i == 0 ? 'Start: ${history[0]}' : record.describePoint(i),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 4),
          child: Text('Recent ${game.resultNounPlural}', style: section),
        ),
        if (record.tiles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'No ${game.resultNounPlural} yet.',
              style: d.body(15, color: d.muted),
            ),
          ),
        for (final (i, tile) in record.tiles.indexed) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: SpecRule(verticalPadding: 0),
            ),
          tile,
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
