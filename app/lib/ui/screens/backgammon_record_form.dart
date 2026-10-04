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
    this.recentOpponentIds = const [],
  });

  final Player me;
  final List<Player> players;
  final String? initialOpponentId;

  /// Who the member played lately in this game, most recent first.
  final List<String> recentOpponentIds;

  @override
  State<BackgammonRecordForm> createState() => _BackgammonRecordFormState();
}

class _BackgammonRecordFormState extends State<BackgammonRecordForm>
    with SendsForConfirmation {
  late String? _opponentId = widget.initialOpponentId;
  int _matchLength = 5;
  Outcome? _outcome;
  int? _loserScore;
  bool _rated = true;

  Player? get _opponent =>
      widget.players.where((p) => p.id == _opponentId).firstOrNull;

  /// The loser's points, which the match length caps at one short of a win.
  /// A match to 1 can only end 1-0, so it needs no answer.
  int? get _loserPoints => _matchLength == 1 ? 0 : _loserScore;

  void _setLength(int length) => setState(() {
    _matchLength = length;
    final loser = _loserScore;
    if (loser != null && loser >= length) _loserScore = length - 1;
  });

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final opponent = _opponent;
    final outcome = _outcome;
    final loserPoints = _loserPoints;
    final won = outcome == Outcome.win;
    // The winner always scores the match length; only the loser's points vary.
    final scored = outcome != null && loserPoints != null;
    final myScore = scored ? (won ? _matchLength : loserPoints) : null;
    final opponentScore = scored ? (won ? loserPoints : _matchLength) : null;
    final preview = opponent != null && scored
        ? BackgammonPreview(
            me: widget.me,
            opponent: opponent,
            won: won,
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
            recentIds: widget.recentOpponentIds,
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
          Text('Result', style: label),
          const SizedBox(height: 8),
          SegmentedButton<Outcome>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: Outcome.win, label: Text('I won')),
              ButtonSegment(value: Outcome.loss, label: Text('I lost')),
            ],
            selected: {?outcome},
            onSelectionChanged: (s) => setState(() => _outcome = s.firstOrNull),
          ),
          if (outcome != null) ...[
            const SizedBox(height: 24),
            Text(
              won
                  ? '${opponent?.displayName ?? 'Your opponent'}\'s points'
                  : 'Your points',
              style: label,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var points = 0; points < _matchLength; points++)
                  ChoiceChip(
                    label: Text('$points'),
                    selected: points == loserPoints,
                    onSelected: (_) => setState(() => _loserScore = points),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          RatedSwitch(
            rated: _rated,
            onChanged: (v) => setState(() => _rated = v),
          ),
          const SizedBox(height: 20),
          RatingPreview(
            rated: _rated,
            emptyHint:
                'Pick an opponent, the result and the loser\'s points to see '
                'how ratings change.',
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
              if (outcome == null) 'a result',
              if (loserPoints == null) 'the loser\'s points',
            ],
            onPressed:
                opponent == null || myScore == null || opponentScore == null
                ? null
                : () => sendForConfirmation(
                    game: Game.backgammon,
                    opponentName: opponent.displayName,
                    rated: _rated,
                    request: (repo) => repo.requestBackgammonMatch(
                      opponentId: opponent.id,
                      matchLength: _matchLength,
                      myScore: myScore,
                      opponentScore: opponentScore,
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
