import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../../features.dart';
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

/// [id]'s profile in [mode], or null once that member deleted their account:
/// their results stay in the history, but there is no profile to open.
String? _profilePath(GameMode mode, String id, Set<String> memberIds) =>
    memberIds.contains(id)
    ? Game.of(mode.type).path('players/$id?mode=${mode.key}')
    : null;

/// "Ana", "Ana & Bo", "Ana, Bo & Cy".
String joinNames(List<String> names) => names.length < 2
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} & ${names.last}';

/// What a seat is called in a sentence: chouette marks its box.
String seatName(GameReport r, Seat s) =>
    r.mode.format == ResultFormat.boxVsTeam && s.side == 1
    ? '${s.name} (box)'
    : s.name;

/// How a result went beyond who won, from [meId]'s side when set: the
/// colours in a chess duel, the score in backgammon and SWU (and SWU's best
/// of), the number of players in a free-for-all. Empty for bughouse. Without date or clock.
String resultDetail(GameReport r, String? meId) => switch (r.mode) {
  GameMode(format: ResultFormat.freeForAll) => '${r.seats.length} players',
  GameMode(type: MatchType.chess, format: ResultFormat.duel) =>
    meId != null
        ? 'Played ${r.colorOf(meId).name}'
        : '${r.seats.first.name} had white',
  GameMode(type: MatchType.chess) => '',
  GameMode(type: MatchType.backgammon) =>
    '${r.scoreFor(meId)} in a match to ${r.matchLength}',
  GameMode(type: MatchType.swu) =>
    '${r.scoreFor(meId)} in games, best of ${r.bestOf == 1 ? 'one' : 'three'}',
};

/// [parts] that aren't empty, joined with [separator].
String joinParts(List<String> parts, String separator) =>
    parts.where((p) => p.isNotEmpty).join(separator);

/// [mode]'s name where a result should say it: always when the build shows
/// game modes, and otherwise only for a result outside the game's standard
/// mode, so it is never taken for one. Empty when it goes unsaid.
String modeLabelFor(BuildContext context, GameMode? mode) {
  if (mode == null) return '';
  if (context.features.showsModesOf(mode.type) ||
      mode != mode.type.defaultMode) {
    return mode.label;
  }
  return '';
}

/// One part of a result sentence: plain text, or a bold name that opens
/// [path] when set.
typedef _Part = ({String text, bool name, String? path});

_Part _text(String text) => (text: text, name: false, path: null);

/// [seats] as linked names joined into one phrase.
List<_Part> _names(Iterable<_Part> names) {
  final list = names.toList();
  return [
    for (final (i, n) in list.indexed) ...[
      if (i > 0) _text(i == list.length - 1 ? ' & ' : ', '),
      n,
    ],
  ];
}

/// One result in a list, in any mode. From the club's view it reads "Ana beat
/// Bo"; from a player's view ([perspectiveId]) it reads "Won against Bo". A
/// free-for-all lists everyone by place. The mode is labelled above.
class ResultTile extends StatelessWidget {
  const ResultTile({
    super.key,
    required this.result,
    required this.memberIds,
    this.perspectiveId,
  });

  final GameResult result;

  /// Members who still have a profile; anyone else's name links nowhere.
  final Set<String> memberIds;
  final String? perspectiveId;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final me = perspectiveId != null && r.involves(perspectiveId!)
        ? perspectiveId
        : null;
    final duel = r.mode.format == ResultFormat.duel;
    // In a duel the whole row opens the opponent, so their name isn't a link.
    _Part name(RatedSeat s) => (
      text: s.playerId == me && !duel ? 'You' : seatName(r, s),
      name: true,
      path: me != null && duel
          ? null
          : _profilePath(r.mode, s.playerId, memberIds),
    );
    final detail = joinParts([
      joinParts([resultDetail(r, me), relativeDate(r.playedAt)], ', '),
      r.clock?.label ?? '',
    ], ' · ');

    final List<_Part> headline;
    final List<RatedSeat> shown;
    if (r.mode.format == ResultFormat.freeForAll) {
      final byFinish = <TwinSunsFinish, List<RatedSeat>>{
        for (final f in TwinSunsFinish.values)
          f: [
            for (final s in r.seats)
              if (r.finishOf(s.playerId) == f) s,
          ],
      }..removeWhere((_, seats) => seats.isEmpty);
      headline = [
        for (final (i, MapEntry(key: finish, value: seats))
            in byFinish.entries.indexed) ...[
          if (i > 0) _text(' · '),
          ..._names(seats.map(name)),
          _text(' ${finish.label.toLowerCase()}'),
        ],
      ];
      shown = [for (final seats in byFinish.values) ...seats];
    } else if (me != null) {
      final verb = switch (r.outcomeFor(me)) {
        Outcome.win => 'Won',
        Outcome.loss => 'Lost',
        Outcome.draw => 'Drew',
      };
      final teammates = r.teammatesOf(me);
      final against = teammates.isEmpty && r.outcomeFor(me) == Outcome.draw
          ? 'with'
          : r.outcomeFor(me) == Outcome.loss
          ? 'to'
          : 'against';
      headline = [
        _text(verb),
        if (teammates.isNotEmpty) ...[
          _text(' with '),
          ..._names(teammates.map(name)),
        ],
        _text(' $against '),
        ..._names(r.opponentsOf(me).map(name)),
      ];
      shown = [r.seatOf(me)!];
    } else {
      // Winners first; for a draw, side 1 (white in chess) first.
      final sides = [...r.sides]
        ..sort((a, b) => b.first.score.compareTo(a.first.score));
      final drawn = sides[0].first.score == sides[1].first.score;
      final ordered = drawn ? r.sides : sides;
      headline = [
        ..._names(ordered[0].map(name)),
        _text(drawn ? ' drew with ' : ' beat '),
        ..._names(ordered[1].map(name)),
      ];
      shown = [ordered[0].first, ordered[1].first];
    }

    return _ResultRow(
      leading: r.mode.type == MatchType.chess && duel
          ? _PieceDot(color: me != null ? r.colorOf(me) : PieceColor.white)
          : null,
      modeLabel: modeLabelFor(context, r.mode),
      headline: headline,
      detail: detail,
      rated: r.rated,
      deltas: [for (final s in shown.take(2)) s.ratingDelta],
      ratingAfter: me == null ? null : r.ratingAfterFor(me),
      path: me != null && duel
          ? _profilePath(r.mode, r.opponentsOf(me).single.playerId, memberIds)
          : null,
    );
  }
}

/// The row every result shares: the mode, a sentence of names with the
/// result, and either your change and new rating or the main changes. An
/// unrated result says so in place of the changes. A row from a duel
/// player's view opens the opponent; elsewhere each name opens that player,
/// so the sentence still reads as one.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    this.leading,
    required this.modeLabel,
    required this.headline,
    required this.detail,
    required this.rated,
    required this.deltas,
    this.ratingAfter,
    this.path,
  });

  final Widget? leading;

  /// Empty when the result's mode goes unsaid; see [modeLabelFor].
  final String modeLabel;
  final List<_Part> headline;
  final String detail;
  final bool rated;
  final List<int> deltas;

  /// The viewer's rating after it, from a player's view.
  final int? ratingAfter;

  /// Where tapping the row goes; null when only the names are links.
  final String? path;

  /// A bold name, linked to its path when it has one. A link is an inline
  /// widget rather than a tappable span so it can take keyboard focus.
  InlineSpan _span(BuildContext context, _Part part) {
    if (!part.name) return TextSpan(text: part.text);
    final bold = context.design.strong(16);
    final path = part.path;
    if (path == null) return TextSpan(text: part.text, style: bold);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _NameLink(
        name: part.text,
        style: bold.copyWith(decoration: TextDecoration.underline),
        onOpen: () => context.go(path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final after = ratingAfter;
    final trailing = rated
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: after != null
                ? [
                    DeltaText(deltas.single, size: 16),
                    Text('$after', style: d.number(13, color: d.muted)),
                  ]
                : [for (final delta in deltas) DeltaText(delta, size: 15)],
          )
        : Text(
            'Unrated',
            style: d.body(13, color: d.muted, weight: FontWeight.w600),
          );
    final path = this.path;

    return InkWell(
      onTap: path == null ? null : () => context.go(path),
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
                  if (modeLabel.isNotEmpty) ...[
                    ModeChip(modeLabel),
                    const SizedBox(height: 4),
                  ],
                  Text.rich(
                    TextSpan(
                      children: [
                        for (final part in headline) _span(context, part),
                      ],
                    ),
                    style: d.body(16),
                  ),
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

/// A mode's name as a small tag over a result.
class ModeChip extends StatelessWidget {
  const ModeChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: d.highlight,
        borderRadius: d.borderRadius,
      ),
      child: Text(
        label.toUpperCase(),
        style: d.body(11, color: d.accent, weight: FontWeight.w700),
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
