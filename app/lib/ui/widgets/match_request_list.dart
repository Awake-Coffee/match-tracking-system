import 'package:flutter/material.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../game.dart';
import '../ladder/ladder_view.dart' show ordinal;
import 'match_tile.dart';
import 'surface.dart';

/// What to tell a member who just confirmed [result].
String _confirmedMessage(String noun, GameResult result, String meId) {
  if (!result.rated) return '$noun confirmed as unrated. Ratings stay put.';
  final after = result.ratingAfterFor(meId);
  return '$noun confirmed. You\'re now $after '
      '(${formatDelta(result.deltaFor(meId))}).';
}

/// What confirming does to the signed-in member: where they end up and by
/// how much.
typedef RatingImpact = ({int after, int delta});

/// One player of a multiplayer result and where they are with it: "1st",
/// "Irina", "reported".
typedef RosterLine = ({String label, String name, String status, bool isMe});

/// How the result went for [meId], in their words: "you won 5-3", "you came
/// 2nd of 4".
String _myResult(ResultRequest r, String meId) {
  if (r.mode.format == ResultFormat.freeForAll) {
    return 'you came ${ordinal(r.placeOf(meId))} of ${r.seats.length}';
  }
  final outcome = switch (r.outcomeFor(meId)) {
    Outcome.win => 'you won',
    Outcome.loss => 'you lost',
    Outcome.draw when r.mode.type == MatchType.chess => 'it was a draw',
    Outcome.draw => 'you drew',
  };
  return r.mode.type == MatchType.chess
      ? outcome
      : '$outcome ${r.scoreFor(meId)}';
}

/// Who [meId] played with and against, or the format: "You had white",
/// "Match to 5", "With Irina against Matei & Ana", "4 players".
String _setting(ResultRequest r, String meId) => switch (r.mode) {
  GameMode(format: ResultFormat.duel, type: MatchType.chess) =>
    'You had ${r.colorOf(meId).name}',
  GameMode(format: ResultFormat.duel, type: MatchType.backgammon) =>
    'Match to ${r.matchLength}',
  GameMode(format: ResultFormat.duel) => 'Best of three',
  GameMode(format: ResultFormat.freeForAll) => '${r.seats.length} players',
  GameMode(format: ResultFormat.boxVsTeam) => joinParts([
    r.seatOf(meId)!.side == 1
        ? 'You in the box'
        : 'With ${joinNames([for (final s in r.teammatesOf(meId)) s.name])} '
              'against ${r.sides.first.single.name} in the box',
    'match to ${r.matchLength}',
  ], ', '),
  GameMode(format: ResultFormat.teams) =>
    'With ${joinNames([for (final s in r.teammatesOf(meId)) s.name])} '
        'against ${joinNames([for (final s in r.opponentsOf(meId)) s.name])}',
};

/// [id]'s row in [players], if the ladder has loaded them.
Player? _playerById(List<Player> players, String id) {
  for (final p in players) {
    if (p.id == id) return p;
  }
  return null;
}

/// A reported result involving the signed-in member that still waits for
/// confirmation, or that someone declined, in any game and mode.
class PendingResult {
  const PendingResult({
    required this.headline,
    required this.detail,
    this.mode,
    required this.reporterName,
    required this.rated,
    required this.incoming,
    this.reported = false,
    this.declined = false,
    required this.reportedAt,
    this.respondedAt,
    this.impact,
    this.roster = const [],
    required this.respond,
    required this.dismiss,
  });

  /// [r] as the signed-in member [meId] sees it, previewed against
  /// [players] as loaded.
  factory PendingResult.of(
    LadderRepository repo,
    String meId,
    ResultRequest r,
    List<Player> players,
  ) {
    final noun = Game.of(r.mode.type).resultNoun;
    final incoming = r.awaits(meId);
    final declined = r.declinedFor(meId);
    final mine = _myResult(r, meId);
    String nameOf(Seat s) => s.playerId == meId ? 'You' : s.name;
    final othersWaiting = [
      for (final s in r.waitingOn)
        if (s.playerId != meId) s.name,
    ];
    // Results declined before more than two could play don't say who did.
    final decliner =
        r.seatOf(r.declinedBy ?? '')?.name ??
        joinNames([for (final s in r.opponentsOf(meId)) s.name]);
    final standings = [
      for (final s in r.seats)
        if (_playerById(players, s.playerId) case final p?)
          (
            playerId: s.playerId,
            side: s.side,
            score: s.score,
            standing: p.standingIn(r.mode),
          ),
    ];
    final delta = r.rated && !declined && standings.length == r.seats.length
        ? ratingChanges(r.mode.type, standings)[meId]
        : null;
    return PendingResult(
      headline: incoming
          ? '${r.reporterName} says $mine'
          : declined
          ? '$decliner declined your $noun'
          : 'Waiting for ${joinNames(othersWaiting)} to confirm',
      detail: joinParts([
        joinParts([_setting(r, meId), if (!incoming) mine], ', '),
        r.clock?.label ?? '',
      ], ' · '),
      mode: r.mode,
      reporterName: r.reporterName,
      rated: r.rated,
      incoming: incoming,
      reported: r.requestedBy == meId,
      declined: declined,
      reportedAt: r.createdAt,
      respondedAt: r.respondedAt,
      impact: delta == null
          ? null
          : (
              after:
                  _playerById(players, meId)!.standingIn(r.mode).rating + delta,
              delta: delta,
            ),
      roster: r.mode.format == ResultFormat.duel || declined
          ? const []
          : [
              for (final s in r.seats)
                (
                  label: switch (r.mode.format) {
                    ResultFormat.freeForAll => ordinal(r.placeOf(s.playerId)),
                    ResultFormat.boxVsTeam => s.side == 1 ? 'Box' : 'Team',
                    _ => 'Team ${s.side}',
                  },
                  name: nameOf(s),
                  status: s.playerId == r.requestedBy
                      ? 'reported'
                      : s.confirmed
                      ? 'confirmed'
                      : s.playerId == meId
                      ? 'waiting on you'
                      : 'waiting',
                  isMe: s.playerId == meId,
                ),
            ],
      respond: ({required accept}) async {
        final result = await repo.respondToRequest(r.id, accept: accept);
        if (result != null) {
          return _confirmedMessage(capitalized(noun), result, meId);
        }
        return accept
            ? 'Confirmed. Waiting for ${joinNames(othersWaiting)}.'
            : null;
      },
      dismiss: () => repo.dismissRequest(r.id),
    );
  }

  final String headline;
  final String detail;

  /// The mode it was played in, named ahead of [detail] where the build
  /// shows modes, or the mode isn't the game's standard one.
  final GameMode? mode;

  /// Who reported it, for the decline confirmation.
  final String reporterName;

  /// False for a result that won't move ratings once confirmed.
  final bool rated;

  /// Waiting for the member, who confirms or declines it.
  final bool incoming;

  /// The member reported it, and can withdraw it while it waits.
  final bool reported;

  /// Someone declined a result the member reported; it stays until the
  /// member [dismiss]es it.
  final bool declined;

  /// When the result was reported.
  final DateTime reportedAt;

  /// When it was declined; null while it's still pending.
  final DateTime? respondedAt;

  /// The member's rating after this result and the change, from the ladder
  /// as loaded; null when unrated or the players aren't on the ladder.
  final RatingImpact? impact;

  /// Every player and whether they've confirmed, for results with more than
  /// two; empty for a duel.
  final List<RosterLine> roster;

  /// Accepts or drops the result; returns the message to show, if any.
  final Future<String?> Function({required bool accept}) respond;

  /// Clears a declined result.
  final Future<void> Function() dismiss;
}

/// Asks before declining [name]'s result, because the decline can't be
/// undone. True when the member goes ahead.
Future<bool> confirmDecline(BuildContext context, String name) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Decline $name\'s result?'),
      content: Text('$name will be told, and the result won\'t count.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Decline'),
        ),
      ],
    ),
  );
  return go ?? false;
}

/// Confirm or decline results others reported with you, withdraw your own,
/// and dismiss the ones someone declined.
class PendingResultList extends StatelessWidget {
  const PendingResultList({super.key, required this.results});

  final List<PendingResult> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in results) ...[
            _PendingResultCard(result: r),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _PendingResultCard extends StatefulWidget {
  const _PendingResultCard({required this.result});

  final PendingResult result;

  @override
  State<_PendingResultCard> createState() => _PendingResultCardState();
}

class _PendingResultCardState extends State<_PendingResultCard> {
  bool _busy = false;

  /// Declining asks first; the other answers go straight through.
  Future<void> _respond({required bool accept}) async {
    final r = widget.result;
    if (!accept && r.incoming) {
      if (!await confirmDecline(context, r.reporterName) || !mounted) return;
    }
    await _run(() => r.respond(accept: accept));
  }

  Future<void> _run(Future<String?> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final message = await action();
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } on LadderException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('That didn\'t go through. Check your connection.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// What confirming does to the member's rating, before they decide. Said
  /// in the future tense for a result still waiting on the opponent. A
  /// declined result will never count, so it says nothing.
  Widget? _impactLine(BuildContext context, PendingResult r) {
    if (r.declined) return null;
    final style = context.design.body(14, weight: FontWeight.w600);
    if (!r.rated) return Text('Ratings stay put', style: style);
    final impact = r.impact;
    if (impact == null) return null;
    final lead = r.incoming
        ? 'Confirm and you go to'
        : 'Once confirmed you go to';
    final d = context.design;
    if (d.leaders) {
      // Read like a menu line: what you do, a dotted leader, where you land.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: LeaderRow(
              lead: Text(lead, style: style),
              color: d.muted,
              baselineGap: 5,
            ),
          ),
          Text(
            '${impact.after}',
            style: d.number(17, weight: FontWeight.w700, displayFace: true),
          ),
          const SizedBox(width: 8),
          DeltaText(impact.delta),
        ],
      );
    }
    // One paragraph, so it wraps as a sentence and reads as one.
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: '$lead ${impact.after} ('),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: DeltaText(impact.delta),
          ),
          const TextSpan(text: ')'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final r = widget.result;
    return SpecSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(r.headline, style: d.strong(16)),
          const SizedBox(height: 2),
          Text(
            joinParts([
              modeLabelFor(context, r.mode),
              r.detail,
              if (!r.rated) 'Unrated',
            ], ' · '),
            style: d.body(13, color: d.muted),
          ),
          const SizedBox(height: 2),
          // A decline can surface hours later, so say when it happened.
          Text(switch (r.respondedAt) {
            final at? when r.declined => 'Declined ${relativeAge(at)}',
            _ => 'Reported ${relativeAge(r.reportedAt)}',
          }, style: d.body(13, color: d.muted)),
          if (r.roster.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final line in r.roster) _RosterRow(line: line),
          ],
          if (_impactLine(context, r) case final line?) ...[
            const SizedBox(height: 8),
            line,
          ],
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: r.declined
                ? [
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await r.dismiss();
                              return null;
                            }),
                      child: const Text('Dismiss'),
                    ),
                  ]
                : r.incoming
                ? [
                    OutlinedButton(
                      onPressed: _busy ? null : () => _respond(accept: false),
                      child: const Text('Decline'),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : () => _respond(accept: true),
                      child: const Text('Confirm'),
                    ),
                  ]
                : [
                    if (r.reported)
                      TextButton(
                        onPressed: _busy ? null : () => _respond(accept: false),
                        child: const Text('Withdraw'),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}

/// One player of a multiplayer result on its pending card: their place or
/// side, name and whether they've confirmed.
class _RosterRow extends StatelessWidget {
  const _RosterRow({required this.line});

  final RosterLine line;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final done = line.status == 'reported' || line.status == 'confirmed';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              line.label,
              style: d.body(14, color: d.accent, weight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              line.name,
              overflow: TextOverflow.ellipsis,
              style: d.body(
                14,
                weight: line.isMe ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Text(line.status, style: d.body(13, color: done ? d.win : d.muted)),
        ],
      ),
    );
  }
}
