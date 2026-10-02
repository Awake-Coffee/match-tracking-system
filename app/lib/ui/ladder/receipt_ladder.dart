import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../widgets/surface.dart';
import 'ladder_view.dart';

/// Receipt: one long printed slip, columns aligned like a till roll.
class ReceiptLadder extends StatelessWidget {
  const ReceiptLadder({super.key, required this.data});

  final LadderData data;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final now = data.now;
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${two(now.day)}/${two(now.month)}/${now.year} ${two(now.hour)}:${two(now.minute)}';
    final small = d.body(14, color: d.muted);
    final summary = data.summary;

    Widget cols(String rank, String name, String rec, String rating,
        {TextStyle? style, bool bold = false}) {
      final s = style ?? d.number(16, weight: bold ? FontWeight.w700 : FontWeight.w400);
      return Row(
        children: [
          SizedBox(width: 32, child: Text(rank, style: s)),
          Expanded(child: Text(name, style: s, overflow: TextOverflow.ellipsis)),
          SizedBox(width: 72, child: Text(rec, style: s, textAlign: TextAlign.right)),
          SizedBox(width: 64, child: Text(rating, style: s, textAlign: TextAlign.right)),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: SpecSurface(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: Column(
          children: [
            // Printed header: the one place this app uses capitals.
            Text('AWAKE COFFEE', style: d.display(24, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Chess ladder', style: d.body(16)),
            Text(stamp, style: small),
            const SpecRule(verticalPadding: 16),
            cols('#', 'Player', 'W-L-D', 'Elo', style: d.body(13, color: d.muted)),
            const SizedBox(height: 8),
            for (final (i, p) in data.players.indexed)
              LadderRowTap(
                player: p,
                data: data,
                rank: i + 1,
                child: Container(
                  color: p.id == data.meId ? d.highlight : null,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: cols(
                    '${i + 1}',
                    p.id == data.meId ? '${p.displayName} *' : p.displayName,
                    record(p),
                    '${p.rating}',
                    bold: p.id == data.meId,
                  ),
                ),
              ),
            const SpecRule(verticalPadding: 16),
            Row(children: [
              Expanded(child: Text('Players', style: d.body(15))),
              Text('${data.players.length}', style: d.number(15)),
            ]),
            Row(children: [
              Expanded(child: Text('Games logged', style: d.body(15))),
              Text('${data.gamesLogged}', style: d.number(15)),
            ]),
            if (summary != null) ...[
              const SizedBox(height: 4),
              Row(children: [Expanded(child: Text('* $summary', style: small))]),
            ],
            const SpecRule(verticalPadding: 16),
            Text('THANK YOU FOR PLAYING', style: d.body(14, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
