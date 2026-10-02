import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../../design/design_spec.dart';
import '../../domain/models.dart';
import 'ladder_view.dart';

/// Crema: the top three as espresso cups seen from above, rating floating in
/// the crema; everyone else listed below.
class CupsLadder extends StatelessWidget {
  const CupsLadder({super.key, required this.data});

  final LadderData data;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final players = data.players;
    final podium = players.take(3).toList();
    // Visual order on the podium: 2nd, 1st, 3rd.
    final order = [if (podium.length > 1) 1, 0, if (podium.length > 2) 2];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The ladder', style: d.display(38)),
          const SizedBox(height: 8),
          Text(data.summary ?? 'Everyone starts at 1000.', style: d.body(16, color: d.muted)),
          const SizedBox(height: 28),
          if (podium.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final i in order)
                  Flexible(
                    child: LadderRowTap(
                      player: podium[i],
                      data: data,
                      rank: i + 1,
                      child: _Cup(
                        player: podium[i],
                        rank: i + 1,
                        size: i == 0 ? 120 : 92,
                        isMe: podium[i].id == data.meId,
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 24),
          for (final (i, p) in players.indexed.skip(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LadderRowTap(
                player: p,
                data: data,
                rank: i + 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: p.id == data.meId ? d.highlight : d.surface,
                    borderRadius: d.borderRadius,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text('${i + 1}', style: d.number(15, color: d.muted)),
                      ),
                      Expanded(
                        child: Text(
                          p.id == data.meId ? '${p.displayName} (you)' : p.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: d.display(18),
                        ),
                      ),
                      Text(record(p), style: d.number(13, color: d.muted)),
                      const SizedBox(width: 16),
                      Text('${p.rating}', style: d.number(18, displayFace: true)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cup extends StatelessWidget {
  const _Cup({required this.player, required this.rank, required this.size, required this.isMe});

  final Player player;
  final int rank;
  final double size;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            child: SizedBox(
              width: size * 1.22,
              height: size,
              child: CustomPaint(
                painter: _CupPainter(design: d),
                child: Padding(
                  padding: EdgeInsets.only(right: size * 0.22),
                  child: Center(
                    child: Text(
                      '${player.rating}',
                      style: d.number(size * 0.22, displayFace: true, color: d.onAccent),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            player.displayName,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: d.display(rank == 1 ? 20 : 17, color: isMe ? d.accent : d.ink),
          ),
          Text(
            isMe ? '${ordinal(rank)}, you' : ordinal(rank),
            style: d.body(13, color: d.muted),
          ),
        ],
      ),
    );
  }
}

class _CupPainter extends CustomPainter {
  _CupPainter({required this.design});

  final DesignSpec design;

  @override
  void paint(Canvas canvas, Size size) {
    final d = design;
    final r = size.height / 2;
    final c = Offset(r, r);

    // Handle, pointing right.
    final handle = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(c.dx + r * 0.98, c.dy), width: r * 0.5, height: r * 0.3),
      Radius.circular(r * 0.15),
    );
    canvas.drawRRect(handle, Paint()..color = d.ink);

    // Porcelain rim and the dark inner wall of the cup.
    canvas.drawCircle(c, r * 0.94, Paint()..color = d.ink);
    canvas.drawCircle(c, r * 0.80, Paint()..color = const Color(0xFF3A2416));

    // Crema, lighter in the middle.
    final crema = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(d.accent, Colors.white, 0.18)!,
          d.accent,
          Color.lerp(d.accent, Colors.black, 0.35)!,
        ],
        stops: const [0, 0.7, 1],
      ).createShader(Rect.fromCircle(center: c, radius: r * 0.76));
    canvas.drawCircle(c, r * 0.76, crema);

    final swirl = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.04
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.62), -math.pi * 0.9, math.pi * 0.6, false, swirl);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.54), math.pi * 0.15, math.pi * 0.5, false, swirl);
  }

  @override
  bool shouldRepaint(_CupPainter old) => old.design != design;
}
