import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../../design/design_spec.dart';
import '../../domain/models.dart';
import 'ladder_view.dart';

/// Sunrise: the leader stands in front of a rising sun; everyone else sits
/// in soft pills below.
class SkyLadder extends StatelessWidget {
  const SkyLadder({super.key, required this.data});

  final LadderData data;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final players = data.players;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (players.isNotEmpty)
            LadderRowTap(
              player: players.first,
              data: data,
              rank: 1,
              child: _Dawn(leader: players.first, isMe: players.first.id == data.meId),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
            child: Text(data.summary ?? 'Everyone starts at 1000.',
                style: d.body(16, color: d.muted, weight: FontWeight.w500)),
          ),
          for (final (i, p) in players.indexed.skip(1))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LadderRowTap(
                player: p,
                data: data,
                rank: i + 1,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: p.id == data.meId ? d.highlight : d.surface,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: d.background,
                        child: Text('${i + 1}', style: d.number(16, weight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          p.id == data.meId ? '${p.displayName} (you)' : p.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: d.body(17, weight: FontWeight.w600),
                        ),
                      ),
                      Text('${p.rating}', style: d.number(20, displayFace: true)),
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

class _Dawn extends StatelessWidget {
  const _Dawn({required this.leader, required this.isMe});

  final Player leader;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: CustomPaint(
        painter: _SkyPainter(d),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Good morning', style: d.body(16, weight: FontWeight.w600)),
              const SizedBox(height: 56),
              Text(
                isMe ? '${leader.displayName} (you)' : leader.displayName,
                style: d.display(40),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${leader.rating}', style: d.display(28)),
                  Text('Top of the ladder', style: d.body(15, weight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.design);

  final DesignSpec design;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFBFD7F3), Color(0xFFFFE1BF), Color(0xFFFFC98A)],
          stops: [0, 0.62, 1],
        ).createShader(rect),
    );
    // The sun, half risen behind the leader's name.
    final sun = Offset(size.width * 0.8, size.height * 1.02);
    final r = size.height * 0.6;
    canvas.drawCircle(sun, r * 1.35, Paint()..color = design.accent.withValues(alpha: 0.18));
    canvas.drawCircle(sun, r, Paint()..color = design.accent);
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.design != design;
}
