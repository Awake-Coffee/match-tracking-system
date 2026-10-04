import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../widgets/surface.dart';
import 'ladder_view.dart';

/// Counter: the ladder as the café's letterboard. Everyone who has played is
/// a line on the board, rank, name, a dotted leader and the rating, like a
/// menu's dishes and prices; your own line is the board inverted. Those who
/// have not played follow unranked.
class CounterLadder extends StatelessWidget {
  const CounterLadder({super.key, required this.data});

  final LadderData data;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final players = data.ranked;
    final columnHead = d.display(12, color: d.muted);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.caps('The ladder'), style: d.display(44, height: 1)),
          const SizedBox(height: 10),
          Text(
            data.summary ?? 'Every player at Awake starts at 1000.',
            style: d.body(15, color: d.muted),
          ),
          if (data.chase case final chase?) ...[
            const SizedBox(height: 6),
            Text(chase, style: d.chase()),
          ],
          const SizedBox(height: 24),
          if (players.isEmpty)
            Text('No games yet.', style: d.body(13, color: d.muted))
          else ...[
            // The rows' labels already say rank and rating.
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(d.caps('No. · Player'), style: columnHead),
                    ),
                    Text(d.caps('Rating'), style: columnHead),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            for (final (i, p) in players.indexed)
              LadderRowTap(
                player: p,
                data: data,
                rank: i + 1,
                child: _Line(
                  player: p,
                  standing: data.standingOf(p),
                  rank: i + 1,
                  isMe: p.id == data.meId,
                ),
              ),
          ],
          UnplayedGroup(data: data),
        ],
      ),
    );
  }
}

/// One line of the board: rank, name, leader, rating.
class _Line extends StatelessWidget {
  const _Line({
    required this.player,
    required this.standing,
    required this.rank,
    required this.isMe,
  });

  final Player player;
  final Standing standing;
  final int rank;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    // Your line is the board inverted: background-colored letters on ink.
    final letters = isMe ? d.background : d.ink;
    final quiet = isMe ? d.background : d.muted;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: isMe ? d.ink : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 34,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '$rank'.padLeft(2, '0'),
                style: d.number(15, color: quiet, displayFace: true),
              ),
            ),
          ),
          Expanded(
            child: LeaderRow(
              color: letters.withValues(alpha: 0.4),
              baselineGap: 7,
              lead: Text(
                d.caps(
                  isMe ? '${player.displayName} (you)' : player.displayName,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: d.display(21, color: letters),
              ),
            ),
          ),
          Text(
            '${standing.rating}',
            style: d.number(21, color: letters, displayFace: true),
          ),
        ],
      ),
    );
  }
}
