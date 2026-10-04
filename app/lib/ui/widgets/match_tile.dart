import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/design_scope.dart';
import '../../domain/backgammon.dart';
import '../../domain/models.dart';
import '../../domain/swu.dart';
import '../game.dart';
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

/// How long ago [when] was, for things that just happened: "just now",
/// "5 min ago", "2 h ago", "yesterday", then days and dates like
/// [relativeDate].
String relativeAge(DateTime when, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final elapsed = current.difference(when);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours} h ago';
  final days = DateTime(
    current.year,
    current.month,
    current.day,
  ).difference(DateTime(when.year, when.month, when.day)).inDays;
  if (days <= 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  return relativeDate(when, now: current);
}

/// One game in a list. From the club's view it reads "Ana beat Bo"; from a
/// player's view ([perspectiveId]) it reads "Won against Bo".
class MatchTile extends StatelessWidget {
  const MatchTile({super.key, required this.match, this.perspectiveId});

  final ChessMatch match;
  final String? perspectiveId;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final me = perspectiveId != null && m.involves(perspectiveId!)
        ? perspectiveId
        : null;
    final when = relativeDate(m.playedAt);
    final clock = m.clock;
    final detail = me != null
        ? 'Played ${m.colorOf(me).name}, $when'
        : '${m.whiteName} had white, $when';
    final leading = _PieceDot(
      color: me != null ? m.colorOf(me) : PieceColor.white,
    );
    final fullDetail = clock == null ? detail : '$detail · ${clock.label}';

    if (me != null) {
      final verb = switch (m.outcomeFor(me)) {
        Outcome.win => 'Won against',
        Outcome.loss => 'Lost to',
        Outcome.draw => 'Drew with',
      };
      return _ResultRow.forPlayer(
        leading: leading,
        verb: verb,
        opponentName: m.opponentName(me),
        opponentPath: Game.chess.path('players/${m.opponentId(me)}'),
        detail: fullDetail,
        rated: m.rated,
        delta: m.deltaFor(me),
        ratingAfter: m.ratingAfterFor(me),
      );
    }
    // Winner's change first; for a draw, white first.
    final firstId = m.winnerId ?? m.whiteId;
    final secondId = firstId == m.whiteId ? m.blackId : m.whiteId;
    return _ResultRow.forClub(
      leading: leading,
      firstName: m.winnerName ?? m.whiteName,
      firstPath: Game.chess.path('players/$firstId'),
      verb: m.result == MatchResult.draw ? 'drew with' : 'beat',
      secondName: m.loserName ?? m.blackName,
      secondPath: Game.chess.path('players/$secondId'),
      detail: fullDetail,
      rated: m.rated,
      firstDelta: m.deltaFor(firstId),
      secondDelta: m.deltaFor(secondId),
    );
  }
}

/// One backgammon match in a list, from the club's or a player's view like
/// [MatchTile].
class BackgammonMatchTile extends StatelessWidget {
  const BackgammonMatchTile({
    super.key,
    required this.match,
    this.perspectiveId,
  });

  final BackgammonMatch match;
  final String? perspectiveId;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final me = perspectiveId != null && m.involves(perspectiveId!)
        ? perspectiveId
        : null;
    final detail =
        '${m.scoreFor(me)} in a match to ${m.matchLength}, '
        '${relativeDate(m.playedAt)}';
    if (me != null) {
      return _ResultRow.forPlayer(
        verb: m.wonBy(me) ? 'Won against' : 'Lost to',
        opponentName: m.opponentName(me),
        opponentPath: Game.backgammon.path('players/${m.opponentId(me)}'),
        detail: detail,
        rated: m.rated,
        delta: m.deltaFor(me),
        ratingAfter: m.ratingAfterFor(me),
      );
    }
    return _ResultRow.forClub(
      firstName: m.winnerName,
      firstPath: Game.backgammon.path('players/${m.winnerId}'),
      verb: 'beat',
      secondName: m.loserName,
      secondPath: Game.backgammon.path('players/${m.loserId}'),
      detail: detail,
      rated: m.rated,
      firstDelta: m.winnerRatingDelta,
      secondDelta: m.loserRatingDelta,
    );
  }
}

/// One Star Wars: Unlimited match in a list, from the club's or a player's
/// view like [MatchTile].
class SwuMatchTile extends StatelessWidget {
  const SwuMatchTile({super.key, required this.match, this.perspectiveId});

  final SwuMatch match;
  final String? perspectiveId;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final me = perspectiveId != null && m.involves(perspectiveId!)
        ? perspectiveId
        : null;
    final detail = '${m.scoreFor(me)} in games, ${relativeDate(m.playedAt)}';
    if (me != null) {
      return _ResultRow.forPlayer(
        verb: switch (m.outcomeFor(me)) {
          Outcome.win => 'Won against',
          Outcome.loss => 'Lost to',
          Outcome.draw => 'Drew with',
        },
        opponentName: m.opponentName(me),
        opponentPath: Game.swu.path('players/${m.opponentId(me)}'),
        detail: detail,
        rated: m.rated,
        delta: m.deltaFor(me),
        ratingAfter: m.ratingAfterFor(me),
      );
    }
    // Winner first; for a draw, whoever recorded it.
    final firstId = m.winnerId ?? m.reporterId;
    final secondId = m.opponentId(firstId);
    return _ResultRow.forClub(
      firstName: m.nameOf(firstId),
      firstPath: Game.swu.path('players/$firstId'),
      verb: m.winnerId == null ? 'drew with' : 'beat',
      secondName: m.nameOf(secondId),
      secondPath: Game.swu.path('players/$secondId'),
      detail: detail,
      rated: m.rated,
      firstDelta: m.deltaFor(firstId),
      secondDelta: m.deltaFor(secondId),
    );
  }
}

/// The row all tiles share: "Won against **Bo**" with your change and new
/// rating, or "**Ana** beat **Bo**" with both changes. An unrated result says
/// so in place of the changes. From a player's view the whole row opens the
/// opponent; from the club's view each name opens that player, so the
/// sentence still reads as one.
class _ResultRow extends StatefulWidget {
  const _ResultRow.forPlayer({
    this.leading,
    required this.verb,
    required String opponentName,
    required String this.opponentPath,
    required this.detail,
    required this.rated,
    required int delta,
    required int this.ratingAfter,
  }) : firstName = null,
       firstPath = null,
       secondName = opponentName,
       secondPath = null,
       firstDelta = delta,
       secondDelta = null;

  const _ResultRow.forClub({
    this.leading,
    required String this.firstName,
    required String this.firstPath,
    required this.verb,
    required this.secondName,
    required String this.secondPath,
    required this.detail,
    required this.rated,
    required this.firstDelta,
    required int this.secondDelta,
  }) : opponentPath = null,
       ratingAfter = null;

  final Widget? leading;

  /// Null from a player's view, where the sentence starts with [verb].
  final String? firstName;
  final String verb;
  final String secondName;
  final String detail;
  final bool rated;
  final int firstDelta;
  final int? secondDelta;
  final int? ratingAfter;

  /// Where tapping the row goes: the opponent's profile, from a player's view.
  final String? opponentPath;

  /// Where tapping each name goes, from the club's view.
  final String? firstPath;
  final String? secondPath;

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  /// Tap handlers for the names in the club sentence; they own state, so the
  /// row disposes them.
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  /// A bold name that opens [path] when tapped, or plain bold when null.
  TextSpan _name(String name, String? path, TextStyle bold) {
    if (path == null) return TextSpan(text: name, style: bold);
    final tap = TapGestureRecognizer()..onTap = () => context.push(path);
    _recognizers.add(tap);
    return TextSpan(
      text: name,
      style: bold.copyWith(decoration: TextDecoration.underline),
      recognizer: tap,
      mouseCursor: SystemMouseCursors.click,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final d = context.design;
    final bold = d.body(16, weight: FontWeight.w700);
    // Rebuilt with the row, so drop the previous build's recognizers.
    _disposeRecognizers();
    final first = w.firstName;
    final headline = Text.rich(
      TextSpan(
        children: [
          if (first != null) ...[
            _name(first, w.firstPath, bold),
            TextSpan(text: ' ${w.verb} '),
          ] else
            TextSpan(text: '${w.verb} '),
          _name(w.secondName, w.secondPath, bold),
        ],
      ),
      style: d.body(16),
    );
    final after = w.ratingAfter;
    final second = w.secondDelta;
    final trailing = w.rated
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: after != null
                ? [
                    DeltaText(w.firstDelta, size: 16),
                    Text('$after', style: d.number(13, color: d.muted)),
                  ]
                : [
                    DeltaText(w.firstDelta, size: 15),
                    DeltaText(second!, size: 15),
                  ],
          )
        : Text(
            'Unrated',
            style: d.body(13, color: d.muted, weight: FontWeight.w600),
          );
    final path = w.opponentPath;

    return InkWell(
      onTap: path == null ? null : () => context.push(path),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            if (w.leading case final leading?) ...[
              leading,
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  headline,
                  const SizedBox(height: 2),
                  Text(w.detail, style: d.body(13, color: d.muted)),
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
