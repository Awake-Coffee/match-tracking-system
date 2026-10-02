import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../app_scope.dart';
import '../widgets/load_view.dart';
import '../widgets/surface.dart';

class RecordScreen extends StatelessWidget {
  const RecordScreen({super.key, this.initialOpponentId});

  final String? initialOpponentId;

  @override
  Widget build(BuildContext context) {
    return LoadView(
      load: (repo) => repo.ladder(),
      builder: (context, players, _) {
        final meId = context.repo.me?.id;
        final me = players.where((p) => p.id == meId).firstOrNull;
        return ListView(
          children: [
            const ScreenTitle(
              'Record a game',
              subtitle: 'Log a game you just played. Both ratings update right away.',
            ),
            if (me == null)
              const MessageView(message: 'Sign in to record a game.')
            else if (players.length < 2)
              const MessageView(message: 'You need an opponent. Ask someone to make a profile first.')
            else
              _RecordForm(me: me, players: players, initialOpponentId: initialOpponentId),
          ],
        );
      },
    );
  }
}

class _RecordForm extends StatefulWidget {
  const _RecordForm({required this.me, required this.players, this.initialOpponentId});

  final Player me;
  final List<Player> players;
  final String? initialOpponentId;

  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  late String? _opponentId = widget.players
      .where((p) => p.id == widget.initialOpponentId && p.id != widget.me.id)
      .firstOrNull
      ?.id;
  PieceColor _color = PieceColor.white;
  Outcome? _outcome;
  bool _saving = false;
  String? _error;

  Player? get _opponent => widget.players.where((p) => p.id == _opponentId).firstOrNull;

  Future<void> _save() async {
    final opponent = _opponent;
    final outcome = _outcome;
    if (opponent == null || outcome == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = context.repo;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final match = await repo.recordMatch(
        opponentId: opponent.id,
        myColor: _color,
        myOutcome: outcome,
      );
      final delta = match.deltaFor(widget.me.id);
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Game saved. You\'re now ${match.ratingAfterFor(widget.me.id)} (${formatDelta(delta)}).',
        ),
      ));
      router.go('/');
    } on LadderException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The game wasn\'t saved. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final opponents = widget.players.where((p) => p.id != widget.me.id).toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    final opponent = _opponent;
    final outcome = _outcome;
    final preview = opponent != null && outcome != null
        ? MatchPreview(me: widget.me, opponent: opponent, outcome: outcome)
        : null;
    final label = d.body(15, weight: FontWeight.w700);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Opponent', style: label),
          const SizedBox(height: 8),
          DropdownMenu<String>(
            initialSelection: _opponentId,
            expandedInsets: EdgeInsets.zero,
            enableFilter: true,
            requestFocusOnTap: true,
            hintText: 'Search players',
            onSelected: (id) => setState(() => _opponentId = id),
            dropdownMenuEntries: [
              for (final p in opponents)
                DropdownMenuEntry(value: p.id, label: p.displayName, trailingIcon: Text('${p.rating}')),
            ],
          ),
          const SizedBox(height: 24),
          Text('You played', style: label),
          const SizedBox(height: 8),
          SegmentedButton<PieceColor>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: PieceColor.white, label: Text('White')),
              ButtonSegment(value: PieceColor.black, label: Text('Black')),
            ],
            selected: {_color},
            onSelectionChanged: (s) => setState(() => _color = s.first),
          ),
          const SizedBox(height: 24),
          Text('Result', style: label),
          const SizedBox(height: 8),
          SegmentedButton<Outcome>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: Outcome.win, label: Text('I won')),
              ButtonSegment(value: Outcome.draw, label: Text('Draw')),
              ButtonSegment(value: Outcome.loss, label: Text('I lost')),
            ],
            selected: {?outcome},
            onSelectionChanged: (s) => setState(() => _outcome = s.firstOrNull),
          ),
          const SizedBox(height: 28),
          SpecSurface(
            child: preview == null
                ? Text('Pick an opponent and a result to see how ratings change.',
                    style: d.body(15, color: d.muted))
                : Column(
                    children: [
                      _PreviewRow(
                        name: 'You',
                        before: preview.me.rating,
                        after: preview.myRatingAfter,
                        delta: preview.myDelta,
                      ),
                      const SizedBox(height: 10),
                      _PreviewRow(
                        name: preview.opponent.displayName,
                        before: preview.opponent.rating,
                        after: preview.opponentRatingAfter,
                        delta: preview.opponentDelta,
                      ),
                    ],
                  ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: d.body(15, color: d.loss, weight: FontWeight.w600)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: preview == null || _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save game'),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.name, required this.before, required this.after, required this.delta});

  final String name;
  final int before;
  final int after;
  final int delta;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Row(
      children: [
        Expanded(
          child: Text(name, overflow: TextOverflow.ellipsis, style: d.body(17, weight: FontWeight.w600)),
        ),
        Text('$before to ', style: d.number(16, color: d.muted)),
        Text('$after', style: d.number(18, weight: FontWeight.w700)),
        const SizedBox(width: 12),
        SizedBox(width: 44, child: Align(alignment: Alignment.centerRight, child: DeltaText(delta, size: 16))),
      ],
    );
  }
}
