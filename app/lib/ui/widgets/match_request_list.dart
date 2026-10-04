import 'package:flutter/material.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../domain/backgammon.dart';
import '../../domain/models.dart';
import '../../domain/swu.dart';
import 'match_tile.dart';
import 'surface.dart';

/// What to tell a member who just confirmed [match].
String _confirmedMessage(String noun, RatedGame match, String meId) {
  if (!match.rated) return '$noun confirmed as unrated. Ratings stay put.';
  final after = match.ratingAfterFor(meId);
  final delta = after - match.ratingBeforeFor(meId);
  return '$noun confirmed. You\'re now $after (${formatDelta(delta)}).';
}

/// What confirming does to the signed-in member: where they end up and by
/// how much.
typedef RatingImpact = ({int after, int delta});

/// [id]'s row in [players], if the ladder has loaded them.
Player? _playerById(List<Player> players, String id) {
  for (final p in players) {
    if (p.id == id) return p;
  }
  return null;
}

/// A reported result involving the signed-in member that still waits for
/// the opponent, or that the opponent declined, in any game.
class PendingResult {
  const PendingResult({
    required this.headline,
    required this.detail,
    required this.opponentName,
    required this.rated,
    required this.incoming,
    this.declined = false,
    required this.reportedAt,
    this.impact,
    required this.respond,
    required this.dismiss,
  });

  factory PendingResult.chess(
    LadderRepository repo,
    String meId,
    MatchRequest r,
    List<Player> players,
  ) {
    final incoming = r.awaits(meId);
    final declined = r.declinedFor(meId);
    final myResult = switch (r.outcomeFor(meId)) {
      Outcome.win => 'you won',
      Outcome.loss => 'you lost',
      Outcome.draw => 'it was a draw',
    };
    final me = _playerById(players, meId);
    final opponent = _playerById(players, r.opponentId(meId));
    final preview = r.rated && !declined && me != null && opponent != null
        ? MatchPreview(me: me, opponent: opponent, outcome: r.outcomeFor(meId))
        : null;
    return PendingResult(
      headline: incoming
          ? '${r.opponentName(meId)} says $myResult'
          : declined
          ? '${r.opponentName(meId)} declined your game'
          : 'Waiting for ${r.opponentName(meId)} to confirm',
      detail:
          'You had ${r.colorOf(meId).name}${incoming ? '' : ', $myResult'} · ${r.clock.label}',
      opponentName: r.opponentName(meId),
      rated: r.rated,
      incoming: incoming,
      declined: declined,
      reportedAt: r.createdAt,
      impact: preview == null
          ? null
          : (after: preview.myRatingAfter, delta: preview.myDelta),
      respond: ({required accept}) async {
        final match = await repo.respondToMatchRequest(r.id, accept: accept);
        return match == null ? null : _confirmedMessage('Game', match, meId);
      },
      dismiss: () => repo.dismissMatchRequest(r.id),
    );
  }

  factory PendingResult.backgammon(
    LadderRepository repo,
    String meId,
    BackgammonMatchRequest r,
    List<Player> players,
  ) {
    final incoming = r.awaits(meId);
    final declined = r.declinedFor(meId);
    final myResult =
        '${r.wonBy(meId) ? 'you won' : 'you lost'} ${r.scoreFor(meId)}';
    final me = _playerById(players, meId);
    final opponent = _playerById(players, r.opponentId(meId));
    final preview = r.rated && !declined && me != null && opponent != null
        ? BackgammonPreview(
            me: me,
            opponent: opponent,
            won: r.wonBy(meId),
            matchLength: r.matchLength,
          )
        : null;
    return PendingResult(
      headline: incoming
          ? '${r.opponentName(meId)} says $myResult'
          : declined
          ? '${r.opponentName(meId)} declined your match'
          : 'Waiting for ${r.opponentName(meId)} to confirm',
      detail: 'Match to ${r.matchLength}${incoming ? '' : ', $myResult'}',
      opponentName: r.opponentName(meId),
      rated: r.rated,
      incoming: incoming,
      declined: declined,
      reportedAt: r.createdAt,
      impact: preview == null
          ? null
          : (
              after: preview.me.backgammon.rating + preview.myDelta,
              delta: preview.myDelta,
            ),
      respond: ({required accept}) async {
        final match = await repo.respondToBackgammonMatchRequest(
          r.id,
          accept: accept,
        );
        return match == null ? null : _confirmedMessage('Match', match, meId);
      },
      dismiss: () => repo.dismissBackgammonMatchRequest(r.id),
    );
  }

  factory PendingResult.swu(
    LadderRepository repo,
    String meId,
    SwuMatchRequest r,
    List<Player> players,
  ) {
    final incoming = r.awaits(meId);
    final declined = r.declinedFor(meId);
    final myResult = switch (r.outcomeFor(meId)) {
      Outcome.win => 'you won',
      Outcome.loss => 'you lost',
      Outcome.draw => 'you drew',
    };
    final me = _playerById(players, meId);
    final opponent = _playerById(players, r.opponentId(meId));
    final preview = r.rated && !declined && me != null && opponent != null
        ? SwuPreview(me: me, opponent: opponent, outcome: r.outcomeFor(meId))
        : null;
    return PendingResult(
      headline: incoming
          ? '${r.opponentName(meId)} says $myResult ${r.scoreFor(meId)}'
          : declined
          ? '${r.opponentName(meId)} declined your match'
          : 'Waiting for ${r.opponentName(meId)} to confirm',
      detail: incoming
          ? 'Best of three'
          : 'Best of three, $myResult ${r.scoreFor(meId)}',
      opponentName: r.opponentName(meId),
      rated: r.rated,
      incoming: incoming,
      declined: declined,
      reportedAt: r.createdAt,
      impact: preview == null
          ? null
          : (
              after: preview.me.swu.rating + preview.myDelta,
              delta: preview.myDelta,
            ),
      respond: ({required accept}) async {
        final match = await repo.respondToSwuMatchRequest(r.id, accept: accept);
        return match == null ? null : _confirmedMessage('Match', match, meId);
      },
      dismiss: () => repo.dismissSwuMatchRequest(r.id),
    );
  }

  final String headline;
  final String detail;

  /// Who the member played, for the decline confirmation.
  final String opponentName;

  /// False for a result that won't move ratings once confirmed.
  final bool rated;

  /// Reported against the member, who confirms or declines it; otherwise the
  /// member reported it and can only withdraw it.
  final bool incoming;

  /// The opponent declined a result the member reported; it stays until the
  /// member [dismiss]es it.
  final bool declined;

  /// When the result was reported.
  final DateTime reportedAt;

  /// The member's rating after this result and the change, from the ladder
  /// as loaded; null when unrated or the players aren't on the ladder.
  final RatingImpact? impact;

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
          child: const Text('Keep it'),
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

/// Confirm or decline results reported against you, withdraw your own, and
/// dismiss the ones your opponent declined.
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
      if (!await confirmDecline(context, r.opponentName) || !mounted) return;
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
  /// in the future tense for a result still waiting on the opponent.
  Widget? _impactLine(BuildContext context, PendingResult r) {
    final style = context.design.body(14, weight: FontWeight.w600);
    if (!r.rated) return Text('Ratings stay put', style: style);
    final impact = r.impact;
    if (impact == null) return null;
    final lead = r.incoming
        ? 'Confirm and you go to'
        : 'Once confirmed you go to';
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
          Text(r.headline, style: d.body(16, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            r.rated ? r.detail : '${r.detail} · Unrated',
            style: d.body(13, color: d.muted),
          ),
          const SizedBox(height: 2),
          Text(
            'Reported ${relativeAge(r.reportedAt)}',
            style: d.body(13, color: d.muted),
          ),
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
