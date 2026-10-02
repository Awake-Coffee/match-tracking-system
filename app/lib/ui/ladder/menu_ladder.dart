import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import 'ladder_view.dart';

/// Chalkboard: the ladder written like the specials, with dotted leaders
/// running from each name to its rating.
class MenuLadder extends StatelessWidget {
  const MenuLadder({super.key, required this.data});

  final LadderData data;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Today\'s ladder', style: d.display(42)),
          const SizedBox(height: 8),
          Text(
            data.summary ?? 'Everyone starts at 1000. Win to climb.',
            style: d.body(16, color: d.muted),
          ),
          const SizedBox(height: 28),
          for (final (i, p) in data.players.indexed)
            LadderRowTap(
              player: p,
              data: data,
              rank: i + 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text('${i + 1}',
                          style: d.display(22, color: i == 0 ? d.accent : d.muted)),
                    ),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: d.body(19,
                                weight: FontWeight.w600,
                                color: p.id == data.meId ? d.accent : d.ink),
                          ),
                          Text(
                            p.id == data.meId
                                ? 'You, ${p.gamesPlayed} games'
                                : '${p.gamesPlayed} games',
                            style: d.body(13, color: d.muted),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                        child: CustomPaint(
                          size: const Size(double.infinity, 2),
                          painter: _DotLeader(d.line),
                        ),
                      ),
                    ),
                    Text('${p.rating}', style: d.number(24, displayFace: true)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DotLeader extends CustomPainter {
  _DotLeader(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double x = 2; x < size.width; x += 7) {
      canvas.drawCircle(Offset(x, size.height / 2), 1.2, paint);
    }
  }

  @override
  bool shouldRepaint(_DotLeader old) => old.color != color;
}
