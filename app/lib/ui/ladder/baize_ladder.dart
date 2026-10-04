import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../../design/designs.dart';
import '../../domain/models.dart';
import 'ladder_view.dart';

/// Baize: every player who has played is a board point, ivory and oxblood
/// in turn. The longer the point, the higher the backgammon rating.
class BaizeLadder extends StatelessWidget {
  const BaizeLadder({super.key, required this.data});

  final LadderData data;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final players = data.ranked;
    final top = players.isEmpty ? 0 : data.standingOf(players.first).rating;
    final bottom = players.isEmpty ? 0 : data.standingOf(players.last).rating;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The race', style: d.display(64, height: 0.9)),
          const SizedBox(height: 10),
          Text(
            '${data.summary ?? 'Everyone starts at ${data.game.startingRating}.'} '
            'The longer your point, the further ahead you are.',
            style: d.body(16, color: d.muted),
          ),
          if (data.chase case final chase?) ...[
            const SizedBox(height: 6),
            Text(chase, style: d.chase()),
          ],
          const SizedBox(height: 18),
          for (final (i, p) in players.indexed)
            LadderRowTap(
              player: p,
              data: data,
              rank: i + 1,
              child: _PointRow(
                player: p,
                standing: data.standingOf(p),
                rank: i + 1,
                isMe: p.id == data.meId,
                // Relative to the spread on the ladder, so the race stays
                // readable whether it spans 30 points or 300.
                pointShare: top == bottom
                    ? 1
                    : (data.standingOf(p).rating - bottom) / (top - bottom),
              ),
            ),
          UnplayedGroup(data: data),
        ],
      ),
    );
  }
}

class _PointRow extends StatelessWidget {
  const _PointRow({
    required this.player,
    required this.standing,
    required this.rank,
    required this.isMe,
    required this.pointShare,
  });

  final Player player;
  final Standing standing;
  final int rank;
  final bool isMe;

  /// 0 for the lowest rating on the ladder, 1 for the highest.
  final double pointShare;

  static const _laneWidth = 120.0;
  static const _shortestPoint = 48.0;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final bg = standing;
    final ivory = rank.isOdd;
    final matches = bg.played == 1 ? '1 match' : '${bg.played} matches';
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: isMe ? d.highlight : null,
        borderRadius: d.borderRadius,
        border: isMe ? Border.all(color: d.accent) : null,
      ),
      child: Row(
        children: [
          Container(
            width: _laneWidth,
            height: 40,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: d.surface, width: 2)),
            ),
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(
                    _shortestPoint + (_laneWidth - _shortestPoint) * pointShare,
                    40,
                  ),
                  painter: _PointPainter(
                    ivory ? baizeIvoryPoint : baizeOxbloodPoint,
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 9,
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ivory ? baizeOxbloodPoint : baizeIvoryPoint,
                    ),
                    child: Text(
                      '$rank',
                      style: d.number(
                        12,
                        weight: FontWeight.w700,
                        color: ivory ? d.ink : d.surface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${player.displayName} (you)' : player.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: d.body(16, weight: FontWeight.w700),
                ),
                Text(
                  '$matches, ${bg.wins}-${bg.losses}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: d.number(12, color: d.muted),
                ),
              ],
            ),
          ),
          Text(
            '${bg.rating}',
            style: d.number(26, displayFace: true, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// A board point lying on its side, pointing right.
class _PointPainter extends CustomPainter {
  const _PointPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..lineTo(size.width, size.height / 2)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_PointPainter old) => old.color != color;
}
