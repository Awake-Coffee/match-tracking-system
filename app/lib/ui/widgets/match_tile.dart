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

/// [id]'s profile in [game], or null once that member deleted their account:
/// their results stay in the history, but there is no profile to open.
String? _profilePath(Game game, String id, Set<String> memberIds) =>
    memberIds.contains(id) ? game.path('players/$id') : null;

/// One game in a list. From the club's view it reads "Ana beat Bo"; from a
/// player's view ([perspectiveId]) it reads "Won against Bo".
class MatchTile extends StatelessWidget {
  const MatchTile({
    super.key,
    required this.match,
    required this.memberIds,
    this.perspectiveId,
  });

  final ChessMatch match;

  /// Members who still have a profile; anyone else's name links nowhere.
  final Set<String> memberIds;
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
        opponentPath: _profilePath(Game.chess, m.opponentId(me), memberIds),
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
      firstPath: _profilePath(Game.chess, firstId, memberIds),
      verb: m.result == MatchResult.draw ? 'drew with' : 'beat',
      secondName: m.loserName ?? m.blackName,
      secondPath: _profilePath(Game.chess, secondId, memberIds),
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
    required this.memberIds,
    this.perspectiveId,
  });

  final BackgammonMatch match;

  /// Members who still have a profile; anyone else's name links nowhere.
  final Set<String> memberIds;
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
        opponentPath: _profilePath(
          Game.backgammon,
          m.opponentId(me),
          memberIds,
        ),
        detail: detail,
        rated: m.rated,
        delta: m.deltaFor(me),
        ratingAfter: m.ratingAfterFor(me),
      );
    }
    return _ResultRow.forClub(
      firstName: m.winnerName,
      firstPath: _profilePath(Game.backgammon, m.winnerId, memberIds),
      verb: 'beat',
      secondName: m.loserName,
      secondPath: _profilePath(Game.backgammon, m.loserId, memberIds),
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
  const SwuMatchTile({
    super.key,
    required this.match,
    required this.memberIds,
    this.perspectiveId,
  });

  final SwuMatch match;

  /// Members who still have a profile; anyone else's name links nowhere.
  final Set<String> memberIds;
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
        opponentPath: _profilePath(Game.swu, m.opponentId(me), memberIds),
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
      firstPath: _profilePath(Game.swu, firstId, memberIds),
      verb: m.winnerId == null ? 'drew with' : 'beat',
      secondName: m.nameOf(secondId),
      secondPath: _profilePath(Game.swu, secondId, memberIds),
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
class _ResultRow extends StatelessWidget {
  const _ResultRow.forPlayer({
    this.leading,
    required this.verb,
    required String opponentName,
    required this.opponentPath,
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
    required this.firstPath,
    required this.verb,
    required this.secondName,
    required this.secondPath,
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
  /// Null when there is nowhere to go (a deleted member), as from the club's.
  final String? opponentPath;

  /// Where tapping each name goes, from the club's view; null for a deleted
  /// member, whose name is then plain bold.
  final String? firstPath;
  final String? secondPath;

  /// A bold name, linked to [path] when it is set. A link is an inline
  /// widget rather than a tappable span so it can take keyboard focus.
  InlineSpan _name(BuildContext context, String name, String? path) {
    final bold = context.design.body(16, weight: FontWeight.w700);
    if (path == null) return TextSpan(text: name, style: bold);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _NameLink(
        name: name,
        style: bold.copyWith(decoration: TextDecoration.underline),
        onOpen: () => context.push(path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final first = firstName;
    final headline = Text.rich(
      TextSpan(
        children: [
          if (first != null) ...[
            _name(context, first, firstPath),
            TextSpan(text: ' $verb '),
          ] else
            TextSpan(text: '$verb '),
          _name(context, secondName, secondPath),
        ],
      ),
      style: d.body(16),
    );
    final after = ratingAfter;
    final second = secondDelta;
    final trailing = rated
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: after != null
                ? [
                    DeltaText(firstDelta, size: 16),
                    Text('$after', style: d.number(13, color: d.muted)),
                  ]
                : [
                    DeltaText(firstDelta, size: 15),
                    DeltaText(second!, size: 15),
                  ],
          )
        : Text(
            'Unrated',
            style: d.body(13, color: d.muted, weight: FontWeight.w600),
          );
    final path = opponentPath;

    return InkWell(
      onTap: path == null ? null : () => context.push(path),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            if (leading case final leading?) ...[
              leading,
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  headline,
                  const SizedBox(height: 2),
                  Text(detail, style: d.body(13, color: d.muted)),
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

/// A player's name inside a result sentence that opens their profile: a link
/// to screen readers, reachable with Tab, opened by a tap, Enter or Space,
/// and ringed in the design's accent while keyboard focus is on it.
class _NameLink extends StatefulWidget {
  const _NameLink({
    required this.name,
    required this.style,
    required this.onOpen,
  });

  final String name;
  final TextStyle style;
  final VoidCallback onOpen;

  @override
  State<_NameLink> createState() => _NameLinkState();
}

class _NameLinkState extends State<_NameLink> {
  /// True only for keyboard focus, so a click leaves no ring behind.
  bool _ring = false;

  void _open() => widget.onOpen();

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Semantics(
      link: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (shown) => setState(() => _ring = shown),
        // The web build maps Enter to ButtonActivateIntent and Space to
        // ActivateIntent; other platforms map both to ActivateIntent.
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _open(),
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) => _open(),
          ),
        },
        child: GestureDetector(
          onTap: _open,
          // Drawn outside the name, so the ring moves nothing in the line.
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(
                color: _ring ? d.accent : Colors.transparent,
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
              borderRadius: d.borderRadius,
            ),
            // The sentence around it already scales this inline widget.
            child: Text(
              widget.name,
              style: widget.style,
              textScaler: TextScaler.noScaling,
            ),
          ),
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
