import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../../design/designs.dart';
import '../../domain/models.dart';
import 'ladder_view.dart';

/// Holotable: the ladder is a route where the distance between two players
/// is their rating gap. Players at or above the starting rating are in the
/// space arena; the route crosses the start line into the ground arena.
class RouteLadder extends StatelessWidget {
  const RouteLadder({super.key, required this.data});

  final LadderData data;

  /// Most height all rating gaps together may take, so a ladder spanning
  /// 300 points stays as scannable as one spanning 30.
  static const _routeBudget = 240.0;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final game = data.game;
    final start = game.startingRating;
    final players = data.ranked;
    final ratings = [for (final p in players) game.ratingOf(p), start];
    final spread = ratings.reduce(math.max) - ratings.reduce(math.min);
    final pixelsPerPoint = math.min(3.0, _routeBudget / math.max(1, spread));
    final space = players.where((p) => game.ratingOf(p) >= start).toList();
    final ground = players.where((p) => game.ratingOf(p) < start).toList();
    final lowestInSpace = space.isEmpty ? start : game.ratingOf(space.last);
    final highestOnGround = ground.isEmpty
        ? start
        : game.ratingOf(ground.first);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text('The route', style: d.display(34))),
                  if (_chase() case final chase?)
                    Text(chase, style: d.body(14, color: d.muted)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${data.summary ?? 'Everyone starts at $start.'} '
                'Gaps on the line are rating gaps.',
                style: d.body(15, color: d.muted),
              ),
            ],
          ),
        ),
        _Arena(
          label: 'Space arena',
          data: data,
          players: space,
          firstRank: 1,
          pixelsPerPoint: pixelsPerPoint,
          tail: (lowestInSpace - start) * pixelsPerPoint,
        ),
        DesignScope(
          spec: holotableGround,
          child: _Arena(
            label: 'Ground arena',
            data: data,
            players: ground,
            firstRank: space.length + 1,
            pixelsPerPoint: pixelsPerPoint,
            lead: (start - highestOnGround) * pixelsPerPoint,
            leadPoints: space.isEmpty || ground.isEmpty
                ? null
                : lowestInSpace - highestOnGround,
            startLine: start,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: UnplayedGroup(data: data),
        ),
      ],
    );
  }

  /// "10 to pass Irina" for a ranked member below first place.
  String? _chase() {
    final game = data.game;
    final ranked = data.ranked;
    final i = ranked.indexWhere((p) => p.id == data.meId);
    if (i < 1) return null;
    final above = ranked[i - 1];
    final points = game.ratingOf(above) - game.ratingOf(ranked[i]) + 1;
    return '$points to pass ${above.displayName}';
  }
}

/// One arena's stretch of the route, in the [DesignScope] it sits in.
class _Arena extends StatelessWidget {
  const _Arena({
    required this.label,
    required this.data,
    required this.players,
    required this.firstRank,
    required this.pixelsPerPoint,
    this.lead = 0,
    this.tail = 0,
    this.leadPoints,
    this.startLine,
  });

  final String label;
  final LadderData data;
  final List<Player> players;
  final int firstRank;
  final double pixelsPerPoint;

  /// Route before the first player and after the last one, in pixels.
  final double lead;
  final double tail;

  /// The rating gap from the previous arena's last player to this arena's
  /// first, labelled on [lead].
  final int? leadPoints;

  /// The starting rating, drawn as this arena's top edge.
  final int? startLine;

  static const _laneWidth = 72.0;

  Widget _gapBetween(Player above, Player below) {
    final points = data.game.ratingOf(above) - data.game.ratingOf(below);
    return _Gap(height: math.max(4.0, points * pixelsPerPoint), points: points);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final startLine = this.startLine;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: d.background,
        border: startLine == null
            ? null
            : Border(top: BorderSide(color: d.accent)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: _laneWidth / 2 - 1,
            top: 0,
            bottom: 0,
            child: ColoredBox(
              color: d.accent.withValues(alpha: 0.55),
              child: const SizedBox(width: 2),
            ),
          ),
          if (startLine != null)
            Positioned(
              right: 20,
              top: -11,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: d.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Start $startLine',
                  style: d.number(
                    12,
                    color: d.onAccent,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(_laneWidth, 8, 20, 4),
                  child: Text(label, style: d.body(13, color: d.muted)),
                ),
                if (players.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(_laneWidth, 4, 20, 4),
                    child: Text(
                      'Nobody here yet.',
                      style: d.body(15, color: d.muted),
                    ),
                  ),
                _Gap(height: lead, points: leadPoints),
                for (final (i, p) in players.indexed) ...[
                  if (i > 0) _gapBetween(players[i - 1], p),
                  LadderRowTap(
                    player: p,
                    data: data,
                    rank: firstRank + i,
                    child: _Stop(
                      player: p,
                      data: data,
                      leader: firstRank + i == 1,
                    ),
                  ),
                ],
                SizedBox(height: tail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A stretch of route, labelled with the rating gap it stands for when
/// there's room for it.
class _Gap extends StatelessWidget {
  const _Gap({required this.height, this.points});

  final double height;
  final int? points;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final points = this.points;
    return SizedBox(
      height: height,
      child: points == null || height < 16
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: _Arena._laneWidth / 2 + 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('−$points', style: d.number(11, color: d.accent)),
              ),
            ),
    );
  }
}

/// A player's stop on the route.
class _Stop extends StatelessWidget {
  const _Stop({required this.player, required this.data, required this.leader});

  final Player player;
  final LadderData data;
  final bool leader;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final game = data.game;
    final isMe = player.id == data.meId;
    final played = game.playedOf(player);
    final s = player.swu;
    final dot = leader ? 18.0 : 12.0;
    return Container(
      height: 52,
      padding: const EdgeInsets.only(right: 20),
      color: isMe ? d.highlight : null,
      child: Row(
        children: [
          SizedBox(
            width: _Arena._laneWidth,
            child: Center(
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: d.accent,
                  boxShadow: [
                    BoxShadow(
                      color: d.accent.withValues(alpha: 0.6),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${player.displayName} (you)' : player.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: d.body(16, weight: FontWeight.w600),
                ),
                Text(
                  '$played ${played == 1 ? 'match' : 'matches'}, '
                  '${s.wins}-${s.losses}-${s.draws}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: d.number(12, color: d.muted),
                ),
              ],
            ),
          ),
          Text(
            '${game.ratingOf(player)}',
            style: d.number(22, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
