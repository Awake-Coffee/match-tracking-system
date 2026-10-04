import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../../domain/backgammon.dart';
import '../../domain/models.dart';
import '../game.dart';
import '../widgets/record_form.dart';

/// Opponent, match length and final score of a backgammon match.
class BackgammonRecordForm extends StatefulWidget {
  const BackgammonRecordForm({
    super.key,
    required this.me,
    required this.players,
    this.initialOpponentId,
  });

  final Player me;
  final List<Player> players;
  final String? initialOpponentId;

  @override
  State<BackgammonRecordForm> createState() => _BackgammonRecordFormState();
}

class _BackgammonRecordFormState extends State<BackgammonRecordForm>
    with SendsForConfirmation {
  late String? _opponentId = widget.initialOpponentId;
  int _matchLength = 5;
  int _myScore = 0;
  int _opponentScore = 0;
  bool _rated = true;

  Player? get _opponent =>
      widget.players.where((p) => p.id == _opponentId).firstOrNull;

  void _setLength(int length) => setState(() {
    _matchLength = length;
    _myScore = math.min(_myScore, length);
    _opponentScore = math.min(_opponentScore, length);
  });

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final opponent = _opponent;
    final scored = isFinalScore(_matchLength, _myScore, _opponentScore);
    final preview = opponent != null && scored
        ? BackgammonPreview(
            me: widget.me,
            opponent: opponent,
            won: _myScore == _matchLength,
            matchLength: _matchLength,
          )
        : null;
    final label = d.body(15, weight: FontWeight.w700);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Opponent', style: label),
          const SizedBox(height: 8),
          OpponentPicker(
            game: Game.backgammon,
            players: widget.players,
            meId: widget.me.id,
            selectedId: _opponentId,
            onSelected: (id) => setState(() => _opponentId = id),
          ),
          const SizedBox(height: 24),
          Text('Match to', style: label),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final length in backgammonMatchLengths)
                _LengthChoice(
                  length: length,
                  selected: length == _matchLength,
                  onTap: () => _setLength(length),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Final score', style: label),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ScoreStepper(
                  name: 'You',
                  owner: 'your',
                  score: _myScore,
                  max: _matchLength,
                  onChanged: (v) => setState(() => _myScore = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ScoreStepper(
                  name: opponent?.displayName ?? 'Opponent',
                  owner: '${opponent?.displayName ?? 'your opponent'}\'s',
                  score: _opponentScore,
                  max: _matchLength,
                  onChanged: (v) => setState(() => _opponentScore = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          RatedSwitch(
            rated: _rated,
            onChanged: (v) => setState(() => _rated = v),
          ),
          const SizedBox(height: 20),
          RatingPreview(
            rated: _rated,
            emptyHint:
                'Pick an opponent and the final score to see how ratings '
                'change. The winner\'s score is the match length.',
            rows: preview == null
                ? null
                : [
                    (
                      name: 'You',
                      before: preview.me.backgammon.rating,
                      delta: preview.myDelta,
                    ),
                    (
                      name: preview.opponent.displayName,
                      before: preview.opponent.backgammon.rating,
                      delta: preview.opponentDelta,
                    ),
                  ],
          ),
          SendForConfirmationButton(
            error: error,
            saving: saving,
            missing: [
              if (opponent == null) 'an opponent',
              if (!scored) 'a final score',
            ],
            onPressed: opponent == null || !scored
                ? null
                : () => sendForConfirmation(
                    game: Game.backgammon,
                    opponentName: opponent.displayName,
                    rated: _rated,
                    request: (repo) => repo.requestBackgammonMatch(
                      opponentId: opponent.id,
                      matchLength: _matchLength,
                      myScore: _myScore,
                      opponentScore: _opponentScore,
                      rated: _rated,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One match length as a round counter.
class _LengthChoice extends StatelessWidget {
  const _LengthChoice({
    required this.length,
    required this.selected,
    required this.onTap,
  });

  final int length;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Match to $length',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? d.ink : null,
            border: Border.all(color: selected ? d.ink : d.line, width: 2),
          ),
          child: Text(
            '$length',
            style: d.number(
              22,
              displayFace: true,
              color: selected ? d.surface : d.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreStepper extends StatelessWidget {
  const _ScoreStepper({
    required this.name,
    required this.owner,
    required this.score,
    required this.max,
    required this.onChanged,
  });

  final String name;

  /// Possessive used in the button labels, e.g. "your" or "Bogdan's".
  final String owner;
  final int score;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: d.surface, borderRadius: d.borderRadius),
      child: Column(
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: d.body(14, color: d.muted),
          ),
          Text(
            '$score',
            semanticsLabel: '$name: $score',
            style: d.number(72, displayFace: true).copyWith(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.outlined(
                tooltip: 'Lower $owner score',
                onPressed: score > 0 ? () => onChanged(score - 1) : null,
                icon: const Icon(Icons.remove),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Raise $owner score',
                onPressed: score < max ? () => onChanged(score + 1) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
