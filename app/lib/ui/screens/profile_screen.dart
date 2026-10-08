import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../../features.dart';
import '../game.dart';
import '../navigation.dart';
import '../ladder/ladder_view.dart';
import '../widgets/load_view.dart';
import '../widgets/match_tile.dart';
import '../widgets/rating_chart.dart';
import '../widgets/surface.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.game,
    required this.playerId,
    required this.isMe,
    this.initialMode,
  });

  final Game game;
  final String playerId;
  final bool isMe;

  /// The mode to show first; the one the member plays most when null.
  final GameMode? initialMode;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// The mode picked on this screen, over [ProfileScreen.initialMode].
  GameMode? _picked;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final modes = context.features.showsModesOf(game.type);
    return LoadView<_ModeRecord>(
      reloadKey: _picked,
      load: (repo) async {
        final player = await repo.player(widget.playerId);
        final mode = modes
            ? _picked ?? widget.initialMode ?? player.mostPlayedIn(game.type)
            : game.type.defaultMode;
        // Opponents who deleted their account stay in the results unlinked.
        final members = await repo.members();
        return _ModeRecord(
          player: player,
          mode: mode,
          results: await repo.results(
            game.type,
            mode: mode,
            playerId: widget.playerId,
            limit: 500,
          ),
          memberIds: {for (final p in members) p.id},
          // How far the next rung up is, from the ladder the ladder screen
          // ranks by.
          chase: widget.isMe
              ? LadderData(
                  mode: mode,
                  players: ladderOf(members, mode),
                  meId: widget.playerId,
                  onOpen: (_) {},
                  now: DateTime.now(),
                ).chase
              : null,
        );
      },
      builder: (context, record, _) => _Profile(
        game: game,
        record: record,
        isMe: widget.isMe,
        onMode: (mode) => setState(() => _picked = mode),
      ),
    );
  }
}

/// A player's standing and results in one mode, ready to show.
class _ModeRecord {
  /// [results] newest first; only rated ones are on the rating line.
  /// [memberIds] are the members who still have a profile to link to.
  _ModeRecord({
    required this.player,
    required this.mode,
    required List<GameResult> results,
    required Set<String> memberIds,
    this.chase,
  }) : standing = player.standingIn(mode),
       _ratedOldestFirst = results.reversed.where((r) => r.rated).toList(),
       tiles = [
         for (final r in results.take(20))
           ResultTile(
             result: r,
             memberIds: memberIds,
             perspectiveId: player.id,
           ),
       ];

  final Player player;
  final GameMode mode;
  final Standing standing;
  final List<GameResult> _ratedOldestFirst;

  /// The 20 most recent results, newest first.
  final List<Widget> tiles;

  /// "10 to pass Irina", shown under the rating; null when nobody is above.
  final String? chase;

  /// Rating at the start and after each result, oldest first.
  late final List<int> history = ratingHistory(
    player.id,
    _ratedOldestFirst,
    start: mode.type.startingRating,
  );

  List<(String, int)> get stats {
    final noun = Game.of(mode.type).resultNounPlural;
    return [
      (capitalized(noun), standing.played),
      ('Won', standing.wins),
      ('Lost', standing.losses),
      // Backgammon can't be drawn.
      if (mode.type != MatchType.backgammon) ('Drawn', standing.draws),
      ('Peak', standing.peakRating),
    ];
  }

  /// Chart tooltip for history point i ≥ 1: "Match 3: Beat Bo 5-3".
  String describePoint(int i) {
    final r = _ratedOldestFirst[i - 1];
    final id = player.id;
    final noun = Game.of(mode.type).resultNoun;
    final what = r.mode.format == ResultFormat.freeForAll
        ? '${r.finishOf(id).label} of ${r.seats.length}'
        : '${switch (r.outcomeFor(id)) {
                Outcome.win => 'Beat',
                Outcome.loss => 'Lost to',
                Outcome.draw => 'Drew with',
              }} ${joinNames([for (final s in r.opponentsOf(id)) s.name])}'
              '${mode.type == MatchType.chess ? '' : ' ${r.scoreFor(id)}'}';
    return '${capitalized(noun)} $i: $what\n'
        '${history[i]} (${formatDelta(r.deltaFor(id))})';
  }
}

class _Profile extends StatelessWidget {
  const _Profile({
    required this.game,
    required this.record,
    required this.isMe,
    required this.onMode,
  });

  final Game game;
  final _ModeRecord record;
  final bool isMe;
  final ValueChanged<GameMode> onMode;

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
                  onPressed: () => context.go(game.path('settings')),
                )
              else
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.close),
                  onPressed: () => goBack(context, fallback: game.path()),
                ),
            ],
          ),
        ),
        if (context.features.showsModesOf(game.type))
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: DropdownMenu<GameMode>(
              initialSelection: record.mode,
              expandedInsets: EdgeInsets.zero,
              label: const Text('Mode'),
              onSelected: (m) {
                if (m != null && m != record.mode) onMode(m);
              },
              dropdownMenuEntries: [
                for (final m in game.modes)
                  DropdownMenuEntry(
                    value: m,
                    label: m.label,
                    trailingIcon: Text('${p.standingIn(m).rating}'),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: SpecSurface(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // "Backgammon rating" in the game's original mode,
                  // "Chess960 rating" in any other.
                  '${record.mode == game.type.defaultMode ? game.label : record.mode.label} rating',
                  style: d.body(14, color: d.muted, weight: FontWeight.w600),
                ),
                Text(
                  '${record.standing.rating}',
                  style: d.display(64, height: 1.05),
                ),
                if (record.chase case final chase?)
                  Text(chase, style: d.chase()),
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
              onPressed: () => context.go(
                game.path('record?opponent=${p.id}&mode=${record.mode.key}'),
              ),
              child: Text('Record a $noun with ${p.displayName}'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
          child: Text(d.caps('Rating over time'), style: section),
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
          child: Text(
            d.caps('Recent ${game.resultNounPlural}'),
            style: section,
          ),
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
