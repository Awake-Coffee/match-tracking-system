import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../app_scope.dart';
import '../game.dart';
import '../ladder/baize_ladder.dart';
import '../ladder/counter_ladder.dart';
import '../ladder/ladder_view.dart';
import '../ladder/route_ladder.dart';
import '../widgets/load_view.dart';
import '../widgets/match_request_list.dart';
import '../widgets/surface.dart';

/// Every member and the game's results waiting on or declined for the
/// signed-in member, with the cards for those results, which preview their
/// rating change against those same members. Fetched one after the other so
/// a failed members fetch never leaves the requests future unawaited.
Future<(List<Player>, List<PendingResult>)> _membersAndPending(
  LadderRepository repo,
  Game game,
) async {
  final meId = repo.me!.id;
  final members = await repo.members();
  final requests = await repo.requests();
  return (
    members,
    [
      for (final r in requests)
        if (r.mode.type == game.type) PendingResult.of(repo, meId, r, members),
    ],
  );
}

/// A game's ladders, one card per mode with the member's place in it, under
/// the results waiting for them. The modes they play come first.
class LadderScreen extends StatelessWidget {
  const LadderScreen({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final meId = context.repo.me?.id;
    return LoadView(
      load: (repo) => _membersAndPending(repo, game),
      builder: (context, data, _) {
        final (members, pending) = data;
        if (members.isEmpty) {
          return MessageView(
            message: 'No one is on the ladder yet.',
            actionLabel: 'Record the first ${game.resultNoun}',
            onAction: () => context.go(game.path('record')),
          );
        }
        final me = members.where((p) => p.id == meId).firstOrNull;
        bool played(GameMode m) => (me?.standingIn(m).played ?? 0) > 0;
        final modes = [
          ...game.modes.where(played),
          ...game.modes.where((m) => !played(m)),
        ];
        final d = context.design;
        void open(GameMode mode) => context.go(game.path('ladder/${mode.key}'));
        return ListView(
          children: [
            PendingResultList(results: pending),
            const ScreenTitle(
              'Ladders',
              subtitle: 'One per mode. Tap one to see everyone.',
            ),
            // A design with leaders lists the modes as lines on its board;
            // the others as cards.
            if (d.leaders) ...[
              const _ModeBoardHead(),
              for (final mode in modes)
                _ModeLine(
                  mode: mode,
                  ladder: ladderOf(members, mode),
                  meId: meId,
                  onOpen: () => open(mode),
                ),
            ] else
              for (final mode in modes)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: _ModeCard(
                    mode: mode,
                    ladder: ladderOf(members, mode),
                    meId: meId,
                    onOpen: () => open(mode),
                  ),
                ),
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }
}

/// One mode on the ladders overview: its rules and size, and the member's
/// rank and rating once they've played it.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.ladder,
    required this.meId,
    required this.onOpen,
  });

  final GameMode mode;

  /// Every member in [mode]'s ladder order.
  final List<Player> ladder;
  final String? meId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final ranked = rankedIn(ladder, mode);
    final rank = ranked.indexWhere((p) => p.id == meId) + 1;
    final me = ladder.where((p) => p.id == meId).firstOrNull;
    final shape = RoundedRectangleBorder(
      borderRadius: d.borderRadius,
      side: BorderSide(color: d.line, width: d.lineWidth),
    );
    return Semantics(
      button: true,
      child: Material(
        color: rank > 0 ? d.surface : Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: onOpen,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mode.label, style: d.display(20)),
                      Text(
                        '${mode.rules} · ${ranked.length} ranked',
                        style: d.body(13, color: d.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (rank > 0 && me != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(ordinal(rank), style: d.display(22)),
                      Text(
                        '${me.standingIn(mode).rating}',
                        style: d.number(13, color: d.muted),
                      ),
                    ],
                  )
                else
                  Text('Not played', style: d.body(13, color: d.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The column heads over the mode lines. The lines' labels already say
/// what they hold.
class _ModeBoardHead extends StatelessWidget {
  const _ModeBoardHead();

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final head = d.display(12, color: d.muted);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
        child: Row(
          children: [
            Expanded(child: Text(d.caps('Mode'), style: head)),
            Text(d.caps('You'), style: head),
          ],
        ),
      ),
    );
  }
}

/// One mode as a line on the board: its name, a dotted leader and the
/// member's place and rating in it, its rules and size underneath.
class _ModeLine extends StatelessWidget {
  const _ModeLine({
    required this.mode,
    required this.ladder,
    required this.meId,
    required this.onOpen,
  });

  final GameMode mode;

  /// Every member in [mode]'s ladder order.
  final List<Player> ladder;
  final String? meId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final ranked = rankedIn(ladder, mode);
    final rank = ranked.indexWhere((p) => p.id == meId) + 1;
    final me = ladder.where((p) => p.id == meId).firstOrNull;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: d.line, width: d.lineWidth),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: LeaderRow(
                      color: d.ink.withValues(alpha: 0.4),
                      baselineGap: 7,
                      lead: Text(
                        d.caps(mode.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: d.display(21),
                      ),
                    ),
                  ),
                  if (rank > 0 && me != null) ...[
                    Text(ordinal(rank), style: d.display(21)),
                    const SizedBox(width: 10),
                    Text(
                      '${me.standingIn(mode).rating}',
                      style: d.number(21, color: d.muted, displayFace: true),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        'Not played',
                        style: d.body(13, color: d.muted),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${mode.rules} · ${ranked.length} ranked',
                style: d.body(13, color: d.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One mode's ladder in its game's style, under the results waiting for the
/// member.
class ModeLadderScreen extends StatelessWidget {
  const ModeLadderScreen({super.key, required this.mode});

  final GameMode mode;

  @override
  Widget build(BuildContext context) {
    final game = Game.of(mode.type);
    final meId = context.repo.me?.id;
    return LoadView(
      load: (repo) => _membersAndPending(repo, game),
      builder: (context, data, _) {
        final (members, pending) = data;
        final d = context.design;
        final ladder = LadderData(
          mode: mode,
          players: ladderOf(members, mode),
          meId: meId,
          now: DateTime.now(),
          onOpen: (p) => p.id == meId
              ? context.go(game.path('me?mode=${mode.key}'))
              : context.go(game.path('players/${p.id}?mode=${mode.key}')),
        );
        return ListView(
          children: [
            PendingResultList(results: pending),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'All ladders',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.go(game.path()),
                  ),
                  // A board titles itself with the mode, so a design with
                  // leaders only says where the arrow goes.
                  Expanded(
                    child: d.leaders
                        ? Text(
                            d.caps('All ladders'),
                            style: d.display(15, color: d.muted),
                          )
                        : Text(mode.label, style: d.display(22)),
                  ),
                ],
              ),
            ),
            switch (game) {
              Game.chess => CounterLadder(data: ladder),
              Game.backgammon => BaizeLadder(data: ladder),
              Game.swu => RouteLadder(data: ladder),
            },
          ],
        );
      },
    );
  }
}
