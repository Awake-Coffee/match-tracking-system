import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../../design/design_spec.dart';
import 'ladder_view.dart';

/// Bauhaus: the top three wear Hartwig's shapes (circle, square, triangle)
/// and every rating is a solid bar.
class BarsLadder extends StatelessWidget {
  const BarsLadder({super.key, required this.data});

  final LadderData data;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final players = data.players;
    final ratings = players.map((p) => p.rating);
    final lo = ratings.isEmpty ? 0 : ratings.reduce(math.min);
    final hi = ratings.isEmpty ? 0 : ratings.reduce(math.max);

    // Bars span 20%-100% of the track so last place still has a bar.
    double fraction(int rating) => hi == lo ? 1 : 0.2 + 0.8 * (rating - lo) / (hi - lo);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ladder', style: d.display(52, height: 1)),
          const SizedBox(height: 8),
          Text(data.summary ?? 'Everyone starts at 1000.', style: d.body(16, color: d.muted)),
          const SizedBox(height: 24),
          DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: d.ink, width: d.lineWidth)),
            child: Column(
              children: [
                for (final (i, p) in players.indexed) ...[
                  if (i > 0) Container(height: 1.5, color: d.ink),
                  LadderRowTap(
                    player: p,
                    data: data,
                    rank: i + 1,
                    child: Container(
                      color: p.id == data.meId ? d.highlight : null,
                      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                      child: Row(
                        children: [
                          _RankMark(rank: i + 1),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.id == data.meId ? '${p.displayName} (you)' : p.displayName,
                                  overflow: TextOverflow.ellipsis,
                                  style: d.display(19),
                                ),
                                const SizedBox(height: 6),
                                FractionallySizedBox(
                                  widthFactor: fraction(p.rating),
                                  alignment: Alignment.centerLeft,
                                  child: Container(height: 10, color: d.ink),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          SizedBox(
                            width: 56,
                            child: Text('${p.rating}',
                                textAlign: TextAlign.right,
                                style: d.number(20, weight: FontWeight.w700, displayFace: true)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RankMark extends StatelessWidget {
  const _RankMark({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    const size = 36.0;
    if (rank > 3) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: Text('$rank', style: d.number(17, weight: FontWeight.w700))),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ShapePainter(rank: rank, design: d),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: rank == 3 ? 10 : 0),
            child: Text(
              '$rank',
              style: d.number(15, weight: FontWeight.w700, color: rank == 3 ? d.ink : Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  _ShapePainter({required this.rank, required this.design});

  final int rank;
  final DesignSpec design;

  @override
  void paint(Canvas canvas, Size size) {
    final d = design;
    switch (rank) {
      case 1:
        canvas.drawCircle(size.center(Offset.zero), size.width / 2, Paint()..color = d.accent);
      case 2:
        canvas.drawRect(Offset.zero & size, Paint()..color = d.win);
      default:
        final path = Path()
          ..moveTo(size.width / 2, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(path, Paint()..color = d.highlight);
        canvas.drawPath(
          path,
          Paint()
            ..color = d.ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
    }
  }

  @override
  bool shouldRepaint(_ShapePainter old) => old.rank != rank || old.design != design;
}
