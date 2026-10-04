import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../../design/designs.dart';
import '../../domain/models.dart';
import '../game.dart';
import '../widgets/record_form.dart';

/// Games won by each side, from the member's side, offered for a result.
const _scoresFor = {
  Outcome.win: [(2, 0), (2, 1), (1, 0)],
  Outcome.draw: [(1, 1)],
  Outcome.loss: [(0, 2), (1, 2), (0, 1)],
};

/// Opponent, result and game score of a best-of-three Star Wars: Unlimited
/// match.
class SwuRecordForm extends StatefulWidget {
  const SwuRecordForm({
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
  State<SwuRecordForm> createState() => _SwuRecordFormState();
}

class _SwuRecordFormState extends State<SwuRecordForm>
    with SendsForConfirmation {
  late String? _opponentId = widget.initialOpponentId;
  Outcome? _outcome;
  (int, int)? _score;
  bool _rated = true;

  Player? get _opponent =>
      widget.players.where((p) => p.id == _opponentId).firstOrNull;

  void _setOutcome(Outcome? outcome) => setState(() {
    _outcome = outcome;
    final scores = _scoresFor[outcome];
    // A draw can only be 1-1, so there's nothing left to pick.
    _score = scores?.length == 1 ? scores!.single : null;
  });

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final opponent = _opponent;
    final outcome = _outcome;
    final score = _score;
    final seats = opponent != null && score != null
        ? <SeatReport>[
            (playerId: widget.me.id, side: 1, score: score.$1),
            (playerId: opponent.id, side: 2, score: score.$2),
          ]
        : null;
    final label = d.body(15, weight: FontWeight.w700);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
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
                onSelectionChanged: (s) => _setOutcome(s.firstOrNull),
              ),
              if (_scoresFor[outcome] case final scores?) ...[
                const SizedBox(height: 24),
                Text('Games, yours first', style: label),
                const SizedBox(height: 8),
                SegmentedButton<(int, int)>(
                  showSelectedIcon: false,
                  emptySelectionAllowed: true,
                  segments: [
                    for (final (mine, theirs) in scores)
                      ButtonSegment(
                        value: (mine, theirs),
                        label: Text(
                          mine + theirs == 1
                              ? '$mine-$theirs on time'
                              : '$mine-$theirs',
                        ),
                      ),
                  ],
                  selected: {?score},
                  onSelectionChanged: (s) =>
                      setState(() => _score = s.firstOrNull),
                ),
              ],
              const SizedBox(height: 24),
              RatedSwitch(
                rated: _rated,
                onChanged: (v) => setState(() => _rated = v),
              ),
            ],
          ),
        ),
        // The preview sits on Holotable's ground, like the bottom of the ladder.
        DesignScope(
          spec: holotableGround,
          child: Builder(
            builder: (context) => ColoredBox(
              color: context.design.background,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RatingPreview(
                      rated: _rated,
                      emptyHint:
                          'Pick an opponent, the result and the games to see '
                          'how ratings change.',
                      rows: seats == null
                          ? null
                          : previewRows(
                              widget.mode,
                              widget.me.id,
                              widget.players,
                              seats,
                            ),
                    ),
                    SendForConfirmationButton(
                      error: error,
                      saving: saving,
                      missing: [
                        if (opponent == null) 'an opponent',
                        if (outcome == null) 'a result',
                        if (outcome != null && score == null) 'the games',
                      ],
                      onPressed: opponent == null || seats == null
                          ? null
                          : () => sendForConfirmation(
                              game: Game.swu,
                              sentTo: opponent.displayName,
                              rated: _rated,
                              request: (repo) => repo.reportResult(
                                ResultReport(
                                  mode: widget.mode,
                                  seats: seats,
                                  rated: _rated,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
