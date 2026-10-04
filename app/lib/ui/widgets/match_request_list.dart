import 'package:flutter/material.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../domain/backgammon.dart';
import '../../domain/models.dart';
import '../../domain/swu.dart';
import 'surface.dart';

/// What to tell a member who just confirmed [match].
String _confirmedMessage(String noun, RatedGame match, String meId) {
  if (!match.rated) return '$noun confirmed as unrated. Ratings stay put.';
  final after = match.ratingAfterFor(meId);
  final delta = after - match.ratingBeforeFor(meId);
  return '$noun confirmed. You\'re now $after (${formatDelta(delta)}).';
}

/// A reported result involving the signed-in member that still waits for
/// the opponent, in either game.
class PendingResult {
  const PendingResult({
    required this.headline,
    required this.detail,
    required this.rated,
    required this.incoming,
    required this.respond,
  });

  factory PendingResult.chess(
    LadderRepository repo,
    String meId,
    MatchRequest r,
  ) {
    final incoming = r.awaits(meId);
    final myResult = switch (r.outcomeFor(meId)) {
      Outcome.win => 'you won',
      Outcome.loss => 'you lost',
      Outcome.draw => 'it was a draw',
    };
    return PendingResult(
      headline: incoming
          ? '${r.opponentName(meId)} says $myResult'
          : 'Waiting for ${r.opponentName(meId)} to confirm',
      detail:
          'You had ${r.colorOf(meId).name}${incoming ? '' : ', $myResult'} · ${r.clock.label}',
      rated: r.rated,
      incoming: incoming,
      respond: ({required accept}) async {
        final match = await repo.respondToMatchRequest(r.id, accept: accept);
        return match == null ? null : _confirmedMessage('Game', match, meId);
      },
    );
  }

  factory PendingResult.backgammon(
    LadderRepository repo,
    String meId,
    BackgammonMatchRequest r,
  ) {
    final incoming = r.awaits(meId);
    final myResult =
        '${r.wonBy(meId) ? 'you won' : 'you lost'} ${r.scoreFor(meId)}';
    return PendingResult(
      headline: incoming
          ? '${r.opponentName(meId)} says $myResult'
          : 'Waiting for ${r.opponentName(meId)} to confirm',
      detail: 'Match to ${r.matchLength}${incoming ? '' : ', $myResult'}',
      rated: r.rated,
      incoming: incoming,
      respond: ({required accept}) async {
        final match = await repo.respondToBackgammonMatchRequest(
          r.id,
          accept: accept,
        );
        return match == null ? null : _confirmedMessage('Match', match, meId);
      },
    );
  }

  factory PendingResult.swu(
    LadderRepository repo,
    String meId,
    SwuMatchRequest r,
  ) {
    final incoming = r.awaits(meId);
    final myResult = switch (r.outcomeFor(meId)) {
      Outcome.win => 'you won',
      Outcome.loss => 'you lost',
      Outcome.draw => 'you drew',
    };
    return PendingResult(
      headline: incoming
          ? '${r.opponentName(meId)} says $myResult ${r.scoreFor(meId)}'
          : 'Waiting for ${r.opponentName(meId)} to confirm',
      detail: incoming
          ? 'Best of three'
          : 'Best of three, $myResult ${r.scoreFor(meId)}',
      rated: r.rated,
      incoming: incoming,
      respond: ({required accept}) async {
        final match = await repo.respondToSwuMatchRequest(r.id, accept: accept);
        return match == null ? null : _confirmedMessage('Match', match, meId);
      },
    );
  }

  final String headline;
  final String detail;

  /// False for a result that won't move ratings once confirmed.
  final bool rated;

  /// Reported against the member, who confirms or declines it; otherwise the
  /// member reported it and can only withdraw it.
  final bool incoming;

  /// Accepts or drops the result; returns the message to show, if any.
  final Future<String?> Function({required bool accept}) respond;
}

/// Confirm or decline results reported against you, withdraw your own.
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

  Future<void> _respond({required bool accept}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final message = await widget.result.respond(accept: accept);
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
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: r.incoming
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
