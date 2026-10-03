import 'package:flutter/material.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../app_scope.dart';
import 'surface.dart';

/// Games the signed-in member is part of that still wait for the opponent:
/// confirm or decline the ones reported against you, withdraw your own.
class MatchRequestList extends StatelessWidget {
  const MatchRequestList({super.key, required this.requests});

  final List<MatchRequest> requests;

  @override
  Widget build(BuildContext context) {
    final meId = context.repo.me?.id;
    if (meId == null || requests.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in requests) ...[
            _MatchRequestCard(request: r, meId: meId),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _MatchRequestCard extends StatefulWidget {
  const _MatchRequestCard({required this.request, required this.meId});

  final MatchRequest request;
  final String meId;

  @override
  State<_MatchRequestCard> createState() => _MatchRequestCardState();
}

class _MatchRequestCardState extends State<_MatchRequestCard> {
  bool _busy = false;

  Future<void> _respond({required bool accept}) async {
    final repo = context.repo;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final match = await repo.respondToMatchRequest(
        widget.request.id,
        accept: accept,
      );
      if (match != null) {
        final delta = match.deltaFor(widget.meId);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Game confirmed. You\'re now ${match.ratingAfterFor(widget.meId)} (${formatDelta(delta)}).',
            ),
          ),
        );
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
    final r = widget.request;
    final me = widget.meId;
    final opponent = r.opponentName(me);
    final incoming = r.awaits(me);
    final myResult = switch (r.outcomeFor(me)) {
      Outcome.win => 'you won',
      Outcome.loss => 'you lost',
      Outcome.draw => 'it was a draw',
    };
    final headline = incoming
        ? '$opponent says $myResult'
        : 'Waiting for $opponent to confirm';
    final detail =
        'You had ${r.colorOf(me).name}${incoming ? '' : ', $myResult'} · ${r.clock.label}';

    return SpecSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(headline, style: d.body(16, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(detail, style: d.body(13, color: d.muted)),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: incoming
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
