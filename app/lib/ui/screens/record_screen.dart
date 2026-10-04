import 'package:flutter/material.dart';

import '../../data/clock_memory.dart';
import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../app_scope.dart';
import '../game.dart';
import '../widgets/clock_picker.dart';
import '../widgets/load_view.dart';
import '../widgets/record_form.dart';
import '../widgets/surface.dart';
import 'backgammon_record_form.dart';
import 'multiplayer_record_forms.dart';
import 'swu_record_form.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({
    super.key,
    required this.game,
    this.initialOpponentId,
    this.initialMode,
  });

  final Game game;
  final String? initialOpponentId;

  /// The mode to record in; the game's first mode when null.
  final GameMode? initialMode;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late GameMode _mode = widget.initialMode ?? widget.game.type.defaultMode;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final noun = game.resultNoun;
    return LoadView(
      load: (repo) async {
        final meId = repo.me?.id;
        // The member's own results, fetched once for both the opponent and
        // (in chess) the clock chips.
        final ownResults = meId == null
            ? Future.value(const <GameResult>[])
            : _ownResults(repo, game.type, meId);
        final recent = meId == null
            ? Future.value(const <String>[])
            : game.recentOpponentsOf(repo, meId, ownResults: ownResults);
        final members = repo.members();
        return (
          members: await members,
          recentIds: await recent,
          ownResults: await ownResults,
        );
      },
      builder: (context, data, _) {
        final members = data.members;
        final meId = context.repo.me?.id;
        final me = members.where((p) => p.id == meId).firstOrNull;
        final initialOpponentId =
            members.any((p) => p.id == widget.initialOpponentId && p.id != meId)
            ? widget.initialOpponentId
            : null;
        final mode = _mode;
        // Duel forms keep what was filled in when the mode changes between
        // duels.
        final formKey = ValueKey(mode.format);
        return ListView(
          children: [
            ScreenTitle(
              'Record a $noun',
              subtitle: mode.format.multiplayer
                  ? 'Log a $noun you just played. Ratings update once '
                        'everyone confirms it.'
                  : 'Log a $noun you just played. Ratings update once your '
                        'opponent confirms it.',
            ),
            if (me == null)
              MessageView(message: 'Sign in to record a $noun.')
            else if (members.length < 2)
              const MessageView(
                message: 'You need an opponent. Ask someone to make a profile first.',
              )
            else ...[
              _ModePicker(
                game: game,
                me: me,
                mode: mode,
                onChanged: (m) => setState(() => _mode = m),
              ),
              switch ((mode.type, mode.format)) {
                (MatchType.chess, ResultFormat.duel) => _ChessRecordForm(
                  key: formKey,
                  mode: mode,
                  me: me,
                  players: members,
                  initialOpponentId: initialOpponentId,
                  recentOpponentIds: data.recentIds,
                  ownGames: data.ownResults,
                ),
                (MatchType.backgammon, ResultFormat.duel) =>
                  BackgammonRecordForm(
                    key: formKey,
                    mode: mode,
                    me: me,
                    players: members,
                    initialOpponentId: initialOpponentId,
                    recentOpponentIds: data.recentIds,
                  ),
                (MatchType.swu, ResultFormat.duel) => SwuRecordForm(
                  key: formKey,
                  mode: mode,
                  me: me,
                  players: members,
                  initialOpponentId: initialOpponentId,
                  recentOpponentIds: data.recentIds,
                ),
                (_, ResultFormat.teams) => BughouseRecordForm(
                  key: formKey,
                  mode: mode,
                  me: me,
                  players: members,
                  recentOpponentIds: data.recentIds,
                  ownGames: data.ownResults,
                ),
                (_, ResultFormat.boxVsTeam) => ChouetteRecordForm(
                  key: formKey,
                  mode: mode,
                  me: me,
                  players: members,
                  recentOpponentIds: data.recentIds,
                ),
                (_, ResultFormat.freeForAll) => FreeForAllRecordForm(
                  key: formKey,
                  mode: mode,
                  me: me,
                  players: members,
                  recentOpponentIds: data.recentIds,
                ),
              },
            ],
          ],
        );
      },
    );
  }
}

/// The member's own results in [type]. Only the record form's shortcuts use
/// them, so a failed load reads as no history rather than blocking the form.
Future<List<GameResult>> _ownResults(
  LadderRepository repo,
  MatchType type,
  String meId,
) async {
  try {
    return await repo.results(type, playerId: meId);
  } catch (_) {
    return const [];
  }
}

/// Which mode the result was played in: a menu of the game's modes with the
/// member's rating in each, the chosen one's rules, and where the member
/// stands on its ladder.
class _ModePicker extends StatelessWidget {
  const _ModePicker({
    required this.game,
    required this.me,
    required this.mode,
    required this.onChanged,
  });

  final Game game;
  final Player me;
  final GameMode mode;
  final ValueChanged<GameMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final standing = me.standingIn(mode);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mode', style: d.body(15, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          DropdownMenu<GameMode>(
            initialSelection: mode,
            expandedInsets: EdgeInsets.zero,
            onSelected: (m) {
              if (m != null) onChanged(m);
            },
            dropdownMenuEntries: [
              for (final m in game.modes)
                DropdownMenuEntry(
                  value: m,
                  label: m.label,
                  trailingIcon: Text('${me.standingIn(m).rating}'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(mode.rules, style: d.body(13, color: d.muted)),
          Text(
            standing.played == 0
                ? 'Rated on its own ladder · you start at ${standing.rating}'
                : 'Rated on its own ladder · you: ${standing.rating} after '
                      '${standing.played} ${standing.played == 1 ? game.resultNoun : game.resultNounPlural}',
            style: d.body(13, color: d.muted),
          ),
        ],
      ),
    );
  }
}

class _ChessRecordForm extends StatefulWidget {
  const _ChessRecordForm({
    super.key,
    required this.mode,
    required this.me,
    required this.players,
    this.initialOpponentId,
    this.recentOpponentIds = const [],
    this.ownGames = const [],
  });

  final GameMode mode;
  final Player me;
  final List<Player> players;
  final String? initialOpponentId;
  final List<String> recentOpponentIds;

  /// The member's own games, newest first, for the clock chips.
  final List<GameResult> ownGames;

  @override
  State<_ChessRecordForm> createState() => _ChessRecordFormState();
}

class _ChessRecordFormState extends State<_ChessRecordForm>
    with SendsForConfirmation {
  late String? _opponentId = widget.initialOpponentId;

  /// Unset until chosen: games can't be edited, so a silent default would
  /// make a wrong colour permanent.
  PieceColor? _color;
  Outcome? _outcome;
  TimeControl? _timeControl;
  ClockSetting? _clock;
  bool _rated = true;

  Player? get _opponent =>
      widget.players.where((p) => p.id == _opponentId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final mode = widget.mode;
    final opponent = _opponent;
    final outcome = _outcome;
    final color = _color;
    final clock = _clock;
    final label = d.body(15, weight: FontWeight.w700);
    // White is side 1.
    final mySide = color == PieceColor.black ? 2 : 1;
    final seats = opponent == null || outcome == null
        ? null
        : <SeatReport>[
            (playerId: widget.me.id, side: mySide, score: outcome.score),
            (playerId: opponent.id, side: 3 - mySide, score: 1 - outcome.score),
          ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Opponent', style: label),
          const SizedBox(height: 8),
          OpponentPicker(
            mode: mode,
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
            onSelectionChanged: (s) => setState(() => _outcome = s.firstOrNull),
          ),
          const SizedBox(height: 24),
          Text('You played', style: label),
          const SizedBox(height: 8),
          SegmentedButton<PieceColor>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: PieceColor.white, label: Text('White')),
              ButtonSegment(value: PieceColor.black, label: Text('Black')),
            ],
            selected: {?color},
            onSelectionChanged: (s) => setState(() => _color = s.firstOrNull),
          ),
          const SizedBox(height: 24),
          Text('Time control', style: label),
          const SizedBox(height: 8),
          ClockPicker(
            meId: widget.me.id,
            ownGames: widget.ownGames,
            onChanged: (preset, clock) => setState(() {
              _timeControl = preset;
              _clock = clock;
            }),
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
                'Pick an opponent and a result to see how ratings change.',
            rows: seats == null
                ? null
                : previewRows(mode, widget.me.id, widget.players, seats),
          ),
          SendForConfirmationButton(
            error: error,
            saving: saving,
            missing: [
              if (opponent == null) 'an opponent',
              if (outcome == null) 'a result',
              if (color == null) 'the colour you played',
              if (_timeControl == null)
                'a time control'
              else if (clock == null)
                'the custom time',
            ],
            onPressed:
                opponent == null ||
                    seats == null ||
                    color == null ||
                    clock == null
                ? null
                : () => sendForConfirmation(
                    game: Game.chess,
                    sentTo: opponent.displayName,
                    rated: _rated,
                    request: (repo) async {
                      await repo.reportResult(
                        ResultReport(
                          mode: mode,
                          seats: seats,
                          rated: _rated,
                          clock: clock,
                        ),
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
