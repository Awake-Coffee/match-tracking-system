import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/clock_memory.dart';
import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../app_scope.dart';
import '../game.dart';
import '../widgets/load_view.dart';
import '../widgets/record_form.dart';
import '../widgets/surface.dart';
import 'backgammon_record_form.dart';
import 'swu_record_form.dart';

class RecordScreen extends StatelessWidget {
  const RecordScreen({super.key, required this.game, this.initialOpponentId});

  final Game game;
  final String? initialOpponentId;

  @override
  Widget build(BuildContext context) {
    final noun = game.resultNoun;
    return LoadView(
      load: game.ladderOf,
      builder: (context, players, _) {
        final meId = context.repo.me?.id;
        final me = players.where((p) => p.id == meId).firstOrNull;
        final initialOpponentId =
            players.any((p) => p.id == this.initialOpponentId && p.id != meId)
            ? this.initialOpponentId
            : null;
        return ListView(
          children: [
            ScreenTitle(
              'Record a $noun',
              subtitle:
                  'Log a $noun you just played. Ratings update once your '
                  'opponent confirms it.',
            ),
            if (me == null)
              MessageView(message: 'Sign in to record a $noun.')
            else if (players.length < 2)
              const MessageView(
                message: 'You need an opponent. Ask someone to make a profile first.',
              )
            else
              switch (game) {
                Game.chess => _ChessRecordForm(
                  me: me,
                  players: players,
                  initialOpponentId: initialOpponentId,
                ),
                Game.backgammon => BackgammonRecordForm(
                  me: me,
                  players: players,
                  initialOpponentId: initialOpponentId,
                ),
                Game.swu => SwuRecordForm(
                  me: me,
                  players: players,
                  initialOpponentId: initialOpponentId,
                ),
              },
          ],
        );
      },
    );
  }
}

class _ChessRecordForm extends StatefulWidget {
  const _ChessRecordForm({
    required this.me,
    required this.players,
    this.initialOpponentId,
  });

  final Player me;
  final List<Player> players;
  final String? initialOpponentId;

  @override
  State<_ChessRecordForm> createState() => _ChessRecordFormState();
}

class _ChessRecordFormState extends State<_ChessRecordForm>
    with SendsForConfirmation {
  late String? _opponentId = widget.initialOpponentId;
  PieceColor _color = PieceColor.white;
  Outcome? _outcome;
  TimeControl? _timeControl;
  int? _customBaseMinutes;
  int? _customExtraSeconds;
  bool _rated = true;

  /// The one-tap clocks: the member's recent ones, or the defaults.
  List<ClockSetting> _recent = defaultClocks;
  bool _showAllClocks = false;

  /// Bumped when a chip sets the clock, so the full list re-reads it.
  int _clockEpoch = 0;
  bool _clocksRequested = false;

  Player? get _opponent =>
      widget.players.where((p) => p.id == _opponentId).firstOrNull;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_clocksRequested) return;
    _clocksRequested = true;
    _loadClocks(context.repo);
  }

  /// Preselects the member's last clock and builds their recent chips from
  /// the last used one and their own games. Without either, the defaults stay.
  Future<void> _loadClocks(LadderRepository repo) async {
    final last = await ClockMemory.last(widget.me.id);
    var mine = const <ChessMatch>[];
    try {
      mine = await repo.matches(playerId: widget.me.id);
    } catch (_) {
      // The chips are a shortcut; the full list still works.
    }
    if (!mounted) return;
    setState(() {
      _recent = recentClocks(last: last, matches: mine);
      // A choice made while this loaded wins.
      if (last != null && _timeControl == null) _choose(last);
    });
  }

  void _choose(ClockSetting clock) {
    _timeControl = clock.preset;
    _customBaseMinutes = clock.customBaseMinutes;
    _customExtraSeconds = clock.customExtraSeconds;
    _clockEpoch++;
  }

  /// The chosen time control, or null until it (and any custom time) is set.
  ClockSetting? get _clock {
    final preset = _timeControl;
    if (preset == null) return null;
    final clock = preset.custom
        ? ClockSetting(
            preset,
            customBaseMinutes: _customBaseMinutes,
            customExtraSeconds: preset.extraName == null
                ? null
                : _customExtraSeconds,
          )
        : ClockSetting(preset);
    return clock.isComplete ? clock : null;
  }

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final opponent = _opponent;
    final outcome = _outcome;
    final clock = _clock;
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
          OpponentPicker(
            game: Game.chess,
            players: widget.players,
            meId: widget.me.id,
            selectedId: _opponentId,
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
            onSelectionChanged: (s) => setState(() => _outcome = s.firstOrNull),
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
          Text('Time control', style: label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _recent)
                ChoiceChip(
                  label: Text(c.label),
                  selected: c == clock,
                  onSelected: (_) => setState(() => _choose(c)),
                ),
              ChoiceChip(
                label: const Text('More…'),
                selected: _showAllClocks,
                onSelected: (v) => setState(() => _showAllClocks = v),
              ),
            ],
          ),
          if (_showAllClocks) ...[
            const SizedBox(height: 12),
            DropdownMenu<TimeControl>(
              key: ValueKey(_clockEpoch),
              initialSelection: _timeControl,
              expandedInsets: EdgeInsets.zero,
              hintText: 'All DGT 2500 presets',
              menuHeight: 360,
              onSelected: (t) => setState(() {
                _timeControl = t;
                _customBaseMinutes = null;
                _customExtraSeconds = null;
              }),
              dropdownMenuEntries: [
                for (final t in TimeControl.values)
                  DropdownMenuEntry(
                    value: t,
                    label: t.label,
                    trailingIcon: Text('${t.dgtOption}'),
                  ),
              ],
            ),
          ],
          if (_timeControl case final preset? when preset.custom) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    label: 'Minutes each',
                    value: _customBaseMinutes,
                    onChanged: (v) => setState(() => _customBaseMinutes = v),
                  ),
                ),
                if (preset.extraName case final extraName?) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      label: '$extraName (s)',
                      value: _customExtraSeconds,
                      onChanged: (v) => setState(() => _customExtraSeconds = v),
                    ),
                  ),
                ],
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
                'Pick an opponent and a result to see how ratings change.',
            rows: preview == null
                ? null
                : [
                    (
                      name: 'You',
                      before: preview.me.rating,
                      delta: preview.myDelta,
                    ),
                    (
                      name: preview.opponent.displayName,
                      before: preview.opponent.rating,
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
              if (clock == null) 'a time control',
            ],
            onPressed: opponent == null || outcome == null || clock == null
                ? null
                : () => sendForConfirmation(
                    game: Game.chess,
                    opponentName: opponent.displayName,
                    rated: _rated,
                    request: (repo) async {
                      await repo.requestMatch(
                        opponentId: opponent.id,
                        myColor: _color,
                        myOutcome: outcome,
                        clock: clock,
                        rated: _rated,
                      );
                      await ClockMemory.remember(widget.me.id, clock);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// A whole-number input for the custom time on the clock. Follows [value]
/// when a chip sets it from outside.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _controller = TextEditingController(
    text: widget.value?.toString(),
  );

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    if (widget.value != int.tryParse(_controller.text)) {
      _controller.text = widget.value?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    decoration: InputDecoration(labelText: widget.label),
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(3),
    ],
    onChanged: (text) => widget.onChanged(int.tryParse(text)),
  );
}
