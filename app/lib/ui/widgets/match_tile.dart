import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/design_scope.dart';
import '../../domain/models.dart';
import 'surface.dart';

String relativeDate(DateTime when, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final days = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(when.year, when.month, when.day)).inDays;
  final time =
      '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
  if (days <= 0) return 'Today, $time';
  if (days == 1) return 'Yesterday, $time';
  if (days < 7) return '$days days ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${when.day} ${months[when.month - 1]}';
}

/// One game in a list. From the club's view it reads "Ana beat Bo"; from a
/// player's view ([perspectiveId]) it reads "Won against Bo".
class MatchTile extends StatelessWidget {
  const MatchTile({super.key, required this.match, this.perspectiveId});

  final ChessMatch match;
  final String? perspectiveId;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final m = match;
    final me = perspectiveId != null && m.involves(perspectiveId!)
        ? perspectiveId
        : null;

    final Widget headline;
    final Widget trailing;
    if (me != null) {
      final verb = switch (m.outcomeFor(me)) {
        Outcome.win => 'Won against',
        Outcome.loss => 'Lost to',
        Outcome.draw => 'Drew with',
      };
      headline = Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$verb '),
            TextSpan(
              text: m.opponentName(me),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        style: d.body(16),
      );
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          DeltaText(m.deltaFor(me), size: 16),
          Text('${m.ratingAfterFor(me)}', style: d.number(13, color: d.muted)),
        ],
      );
    } else {
      final bold = d.body(16, weight: FontWeight.w700);
      headline = Text.rich(
        m.result == MatchResult.draw
            ? TextSpan(
                children: [
                  TextSpan(text: m.whiteName, style: bold),
                  const TextSpan(text: ' drew with '),
                  TextSpan(text: m.blackName, style: bold),
                ],
              )
            : TextSpan(
                children: [
                  TextSpan(text: m.winnerName, style: bold),
                  const TextSpan(text: ' beat '),
                  TextSpan(text: m.loserName, style: bold),
                ],
              ),
        style: d.body(16),
      );
      // Winner's change first; for a draw, white first.
      final firstId = m.winnerId ?? m.whiteId;
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          DeltaText(m.deltaFor(firstId), size: 15),
          DeltaText(-m.deltaFor(firstId), size: 15),
        ],
      );
    }

    final when = relativeDate(m.playedAt);
    final detail = me != null
        ? 'Played ${m.colorOf(me).name}, $when'
        : '${m.whiteName} had white, $when';
    final clock = m.clock;
    final detailWithClock = clock == null ? detail : '$detail · ${clock.label}';

    return InkWell(
      onTap: me == null
          ? null
          : () => context.push('/players/${m.opponentId(me)}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            _PieceDot(color: me != null ? m.colorOf(me) : PieceColor.white),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  headline,
                  const SizedBox(height: 2),
                  Text(detailWithClock, style: d.body(13, color: d.muted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// Small disc showing which color a player had.
class _PieceDot extends StatelessWidget {
  const _PieceDot({required this.color});

  final PieceColor color;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final white = color == PieceColor.white;
    return Semantics(
      label: white ? 'White pieces' : 'Black pieces',
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: d.radius == 0 ? BoxShape.rectangle : BoxShape.circle,
          color: white ? const Color(0xFFF7F7F2) : const Color(0xFF1B1B1B),
          border: Border.all(color: d.line, width: 1.5),
        ),
      ),
    );
  }
}
