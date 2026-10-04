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
    required this.mode,
    required this.me,
    required this.players,
    this.initialOpponentId,
    this.recentOpponentIds = const [],
  });

  final GameMode mode;
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

  /// A loser's score that would win the new length is cleared, not clamped,
  /// so the form never sends a score the member did not pick.
  void _setLength(int length) => setState(() {
    _matchLength = length;
    final loser = _loserScore;
    if (loser != null && loser >= length) _loserScore = null;
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
    // The loser's points do not move ratings: the preview needs the result,
    // with any loser's score to stand in until it's picked.
    final preview = opponent != null && outcome != null
        ? previewRows(widget.mode, widget.me.id, widget.players, [
            (playerId: widget.me.id, side: 1, score: won ? _matchLength : 0),
            (playerId: opponent.id, side: 2, score: won ? 0 : _matchLength),
          ])
        : null;
    final label = d.strong(15);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Opponent', style: label),
          const SizedBox(height: 8),
          OpponentPicker(
            mode: widget.mode,
            players: widget.players,
            meId: widget.me.id,
            selectedId: _opponentId,
            recentIds: widget.recentOpponentIds,
            onSelected: (id) => setState(() => _opponentId = id),
          ),
          const SizedBox(height: 24),
          Text('Match to', style: label),
          const SizedBox(height: 10),
          MatchLengthPicker(length: _matchLength, onChanged: _setLength),
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
          // A match to 1 can only end 1-0: no points row to answer.
          if (outcome != null && _matchLength > 1) ...[
            const SizedBox(height: 24),
            Text(
              won
                  ? '${opponent?.displayName ?? 'Your opponent'}\'s points'
                  : 'Your points',
              style: label,
            ),
            const SizedBox(height: 10),
            LoserPointsPicker(
              matchLength: _matchLength,
              points: loserPoints,
              onChanged: (points) => setState(() => _loserScore = points),
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
                'Pick an opponent and a result to see how ratings change.',
            rows: preview,
          ),
          SendForConfirmationButton(
            error: error,
            saving: saving,
            missing: [
              if (opponent == null) 'an opponent',
              if (outcome == null) 'a result',
              // The points row only appears once a result is picked.
              if (outcome != null && loserPoints == null) 'the loser\'s points',
            ],
            onPressed:
                opponent == null || myScore == null || opponentScore == null
                ? null
                : () => sendForConfirmation(
                    game: Game.backgammon,
                    sentTo: opponent.displayName,
                    rated: _rated,
                    request: (repo) => repo.reportResult(
                      ResultReport(
                        mode: widget.mode,
                        seats: [
                          (playerId: widget.me.id, side: 1, score: myScore),
                          (
                            playerId: opponent.id,
                            side: 2,
                            score: opponentScore,
                          ),
                        ],
                        rated: _rated,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The match lengths offered, as a row of round counters.
class MatchLengthPicker extends StatelessWidget {
  const MatchLengthPicker({
    super.key,
    required this.length,
    required this.onChanged,
  });

  final int length;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      for (final l in backgammonMatchLengths)
        _LengthChoice(
          length: l,
          selected: l == length,
          onTap: () => onChanged(l),
        ),
    ],
  );
}

/// The losing side's points, below the match length.
class LoserPointsPicker extends StatelessWidget {
  const LoserPointsPicker({
    super.key,
    required this.matchLength,
    required this.points,
    required this.onChanged,
  });

  final int matchLength;
  final int? points;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var p = 0; p < matchLength; p++)
        ChoiceChip(
          label: Text('$p'),
          selected: p == points,
          onSelected: (_) => onChanged(p),
        ),
    ],
  );
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
