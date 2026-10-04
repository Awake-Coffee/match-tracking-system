import 'package:flutter/material.dart';

import '../../data/clock_memory.dart';
import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../game.dart';
import '../ladder/ladder_view.dart' show ordinal;
import '../widgets/clock_picker.dart';
import '../widgets/match_tile.dart' show joinNames;
import '../widgets/record_form.dart';
import 'backgammon_record_form.dart';

/// Players picked one at a time into a group: each a removable chip, then
/// the usual picker for the next until there are [max].
class PlayerGroupPicker extends StatelessWidget {
  const PlayerGroupPicker({
    super.key,
    required this.mode,
    required this.players,
    required this.meId,
    required this.recentIds,
    required this.pickedIds,
    required this.max,
    required this.onChanged,
    this.takenIds = const {},
  });

  final GameMode mode;
  final List<Player> players;
  final String meId;
  final List<String> recentIds;
  final List<String> pickedIds;
  final int max;
  final ValueChanged<List<String>> onChanged;

  /// Players picked elsewhere in the form, who aren't offered.
  final Set<String> takenIds;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final p in players) p.id: p};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pickedIds.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in pickedIds)
                InputChip(
                  label: Text(byId[id]?.displayName ?? ''),
                  onDeleted: () => onChanged([
                    for (final other in pickedIds)
                      if (other != id) other,
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (pickedIds.length < max)
          OpponentPicker(
            // A fresh, empty picker after every pick.
            key: ValueKey(pickedIds.join()),
            mode: mode,
            players: players,
            meId: meId,
            selectedId: null,
            recentIds: recentIds,
            takenIds: {...takenIds, ...pickedIds},
            hintText: 'Add a player',
            onSelected: (id) {
              if (id != null) onChanged([...pickedIds, id]);
            },
          ),
      ],
    );
  }
}

/// The names of [ids] in [players], joined: "Irina, Matei & Ana".
String _namesOf(List<Player> players, Iterable<String> ids) => joinNames([
  for (final id in ids) players.firstWhere((p) => p.id == id).displayName,
]);

/// Bughouse: the member and a partner against two opponents, on two clocks
/// set the same way.
class BughouseRecordForm extends StatefulWidget {
  const BughouseRecordForm({
    super.key,
    required this.mode,
    required this.me,
    required this.players,
    this.recentOpponentIds = const [],
    this.ownGames = const [],
  });

  final GameMode mode;
  final Player me;
  final List<Player> players;
  final List<String> recentOpponentIds;

  /// The member's own chess games, newest first, for the clock chips.
  final List<GameResult> ownGames;

  @override
  State<BughouseRecordForm> createState() => _BughouseRecordFormState();
}

class _BughouseRecordFormState extends State<BughouseRecordForm>
    with SendsForConfirmation {
  String? _partnerId;
  List<String> _opponentIds = const [];
  Outcome? _outcome;
  TimeControl? _timeControl;
  ClockSetting? _clock;
  bool _rated = true;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final mode = widget.mode;
    final meId = widget.me.id;
    final partnerId = _partnerId;
    final outcome = _outcome;
    final clock = _clock;
    final label = d.body(15, weight: FontWeight.w700);
    final teamsSet = partnerId != null && _opponentIds.length == 2;
    final seats = !teamsSet || outcome == null
        ? null
        : <SeatReport>[
            for (final id in [meId, partnerId])
              (playerId: id, side: 1, score: outcome.score),
            for (final id in _opponentIds)
              (playerId: id, side: 2, score: 1 - outcome.score),
          ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your partner', style: label),
          const SizedBox(height: 8),
          OpponentPicker(
            mode: mode,
            players: widget.players,
            meId: meId,
            selectedId: partnerId,
            recentIds: widget.recentOpponentIds,
            takenIds: _opponentIds.toSet(),
            onSelected: (id) => setState(() => _partnerId = id),
          ),
          const SizedBox(height: 24),
          Text('Opponents', style: label),
          const SizedBox(height: 8),
          PlayerGroupPicker(
            mode: mode,
            players: widget.players,
            meId: meId,
            recentIds: widget.recentOpponentIds,
            pickedIds: _opponentIds,
            max: 2,
            takenIds: {?partnerId},
            onChanged: (ids) => setState(() => _opponentIds = ids),
          ),
          const SizedBox(height: 24),
          Text('Result', style: label),
          const SizedBox(height: 8),
          SegmentedButton<Outcome>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: Outcome.win, label: Text('We won')),
              ButtonSegment(value: Outcome.draw, label: Text('Draw')),
              ButtonSegment(value: Outcome.loss, label: Text('We lost')),
            ],
            selected: {?outcome},
            onSelectionChanged: (s) => setState(() => _outcome = s.firstOrNull),
          ),
          const SizedBox(height: 24),
          Text('Time control (both clocks)', style: label),
          const SizedBox(height: 8),
          ClockPicker(
            meId: meId,
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
                'Pick both teams and a result to see how ratings change.',
            rows: seats == null
                ? null
                : previewRows(mode, meId, widget.players, seats),
          ),
          SendForConfirmationButton(
            error: error,
            saving: saving,
            missing: [
              if (partnerId == null) 'your partner',
              if (_opponentIds.length < 2) 'two opponents',
              if (outcome == null) 'a result',
              if (_timeControl == null)
                'a time control'
              else if (clock == null)
                'the custom time',
            ],
            onPressed: seats == null || clock == null
                ? null
                : () => sendForConfirmation(
                    game: Game.of(mode.type),
                    sentTo: _namesOf(widget.players, [
                      partnerId!,
                      ..._opponentIds,
                    ]),
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
                      await ClockMemory.remember(meId, clock);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Chouette: one player in the box against a team of 2 to 5 that shares the
/// result, in a match to N points.
class ChouetteRecordForm extends StatefulWidget {
  const ChouetteRecordForm({
    super.key,
    required this.mode,
    required this.me,
    required this.players,
    this.recentOpponentIds = const [],
  });

  final GameMode mode;
  final Player me;
  final List<Player> players;
  final List<String> recentOpponentIds;

  @override
  State<ChouetteRecordForm> createState() => _ChouetteRecordFormState();
}

class _ChouetteRecordFormState extends State<ChouetteRecordForm>
    with SendsForConfirmation {
  /// Whether the member was in the box; unset until chosen.
  bool? _inBox;

  /// The box, when it wasn't the member.
  String? _boxId;

  /// The rest of the team: everyone but the member and the box.
  List<String> _teamIds = const [];
  int _matchLength = 5;
  Outcome? _outcome;
  int? _loserScore;
  bool _rated = true;

  /// A match to 1 can only end 1-0, so it needs no answer.
  int? get _loserPoints => _matchLength == 1 ? 0 : _loserScore;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final mode = widget.mode;
    final meId = widget.me.id;
    final inBox = _inBox;
    final outcome = _outcome;
    final loserPoints = _loserPoints;
    final label = d.body(15, weight: FontWeight.w700);
    // The team counts the member when they weren't the box.
    final teamSize = _teamIds.length + (inBox == false ? 1 : 0);
    final boxId = inBox == true ? meId : _boxId;
    final ready =
        boxId != null &&
        teamSize >= 2 &&
        outcome != null &&
        loserPoints != null;
    final iWon = outcome == Outcome.win;
    // Side 1 is the box; the winner scores the match length.
    final boxWon = inBox == true ? iWon : !iWon;
    final seats = !ready
        ? null
        : <SeatReport>[
            (
              playerId: boxId,
              side: 1,
              score: boxWon ? _matchLength : loserPoints,
            ),
            for (final id in [if (inBox == false) meId, ..._teamIds])
              (
                playerId: id,
                side: 2,
                score: boxWon ? loserPoints : _matchLength,
              ),
          ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('You played', style: label),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: true, label: Text('In the box')),
              ButtonSegment(value: false, label: Text('On the team')),
            ],
            selected: {?inBox},
            onSelectionChanged: (s) => setState(() {
              _inBox = s.firstOrNull;
              _boxId = null;
            }),
          ),
          if (inBox == false) ...[
            const SizedBox(height: 24),
            Text('Box', style: label),
            const SizedBox(height: 8),
            OpponentPicker(
              mode: mode,
              players: widget.players,
              meId: meId,
              selectedId: _boxId,
              recentIds: widget.recentOpponentIds,
              takenIds: _teamIds.toSet(),
              onSelected: (id) => setState(() => _boxId = id),
            ),
          ],
          if (inBox != null) ...[
            const SizedBox(height: 24),
            Text(
              inBox ? 'Team · 2 to 5' : 'Your teammates · 1 to 4',
              style: label,
            ),
            const SizedBox(height: 8),
            PlayerGroupPicker(
              mode: mode,
              players: widget.players,
              meId: meId,
              recentIds: widget.recentOpponentIds,
              pickedIds: _teamIds,
              max: inBox ? 5 : 4,
              takenIds: {?_boxId},
              onChanged: (ids) => setState(() => _teamIds = ids),
            ),
          ],
          const SizedBox(height: 24),
          Text('Match to', style: label),
          const SizedBox(height: 10),
          MatchLengthPicker(
            length: _matchLength,
            onChanged: (length) => setState(() {
              _matchLength = length;
              final loser = _loserScore;
              if (loser != null && loser >= length) _loserScore = null;
            }),
          ),
          const SizedBox(height: 24),
          Text('Result', style: label),
          const SizedBox(height: 8),
          SegmentedButton<Outcome>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: [
              ButtonSegment(
                value: Outcome.win,
                label: Text(inBox == false ? 'We won' : 'I won'),
              ),
              ButtonSegment(
                value: Outcome.loss,
                label: Text(inBox == false ? 'We lost' : 'I lost'),
              ),
            ],
            selected: {?outcome},
            onSelectionChanged: (s) => setState(() => _outcome = s.firstOrNull),
          ),
          if (outcome != null && _matchLength > 1) ...[
            const SizedBox(height: 24),
            Text(
              boxWon ? 'The team\'s points' : 'The box\'s points',
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
                'Pick the box, the team and a result to see how ratings '
                'change.',
            rows: seats == null
                ? null
                : previewRows(mode, meId, widget.players, seats),
          ),
          SendForConfirmationButton(
            error: error,
            saving: saving,
            missing: [
              if (inBox == null) 'where you played',
              if (boxId == null && inBox == false) 'the box',
              if (teamSize < 2) 'the team',
              if (outcome == null) 'a result',
              if (outcome != null && loserPoints == null) 'the loser\'s points',
            ],
            onPressed: seats == null
                ? null
                : () => sendForConfirmation(
                    game: Game.of(mode.type),
                    sentTo: _namesOf(widget.players, [
                      for (final s in seats)
                        if (s.playerId != meId) s.playerId,
                    ]),
                    rated: _rated,
                    request: (repo) => repo.reportResult(
                      ResultReport(mode: mode, seats: seats, rated: _rated),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A free-for-all (Twin Suns): who played, then everyone in finishing order,
/// winner first. Players knocked out together are marked tied.
class FreeForAllRecordForm extends StatefulWidget {
  const FreeForAllRecordForm({
    super.key,
    required this.mode,
    required this.me,
    required this.players,
    this.recentOpponentIds = const [],
  });

  final GameMode mode;
  final Player me;
  final List<Player> players;
  final List<String> recentOpponentIds;

  /// Most players besides the member.
  static const maxOthers = 3;

  @override
  State<FreeForAllRecordForm> createState() => _FreeForAllRecordFormState();
}

class _FreeForAllRecordFormState extends State<FreeForAllRecordForm>
    with SendsForConfirmation {
  /// Everyone, the member included, in finishing order.
  late List<String> _order = [widget.me.id];

  /// Players knocked out together with the one above them.
  Set<String> _tiedWithAbove = const {};
  bool _rated = true;

  List<String> get _others => [
    for (final id in _order)
      if (id != widget.me.id) id,
  ];

  /// Each player's score: how many players finished below them.
  List<SeatReport> get _seats {
    final groups = <List<String>>[];
    for (final id in _order) {
      if (groups.isNotEmpty && _tiedWithAbove.contains(id)) {
        groups.last.add(id);
      } else {
        groups.add([id]);
      }
    }
    final total = _order.length;
    return [
      for (final group in groups)
        for (final id in group)
          (
            playerId: id,
            side: _order.indexOf(id) + 1,
            score: total - _order.indexOf(group.first) - group.length,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final mode = widget.mode;
    final meId = widget.me.id;
    final label = d.body(15, weight: FontWeight.w700);
    final byId = {for (final p in widget.players) p.id: p};
    final ready = _order.length >= 2;
    final seats = _seats;
    final places = {
      for (final s in seats)
        s.playerId: 1 + seats.where((o) => o.score > s.score).length,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Players · 2 to 4', style: label),
          const SizedBox(height: 8),
          PlayerGroupPicker(
            mode: mode,
            players: widget.players,
            meId: meId,
            recentIds: widget.recentOpponentIds,
            pickedIds: _others,
            max: FreeForAllRecordForm.maxOthers,
            onChanged: (ids) => setState(() {
              // New players join at the bottom; the order of the rest stays.
              _order = [
                for (final id in _order)
                  if (id == meId || ids.contains(id)) id,
                for (final id in ids)
                  if (!_order.contains(id)) id,
              ];
              _tiedWithAbove = _tiedWithAbove.intersection(_order.toSet());
            }),
          ),
          if (ready) ...[
            const SizedBox(height: 24),
            Text('Finishing order · drag to reorder', style: label),
            const SizedBox(height: 8),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorderItem: (from, to) => setState(() {
                _order.insert(to, _order.removeAt(from));
                // The winner can't be tied with anyone above.
                _tiedWithAbove = _tiedWithAbove.difference({_order.first});
              }),
              children: [
                for (final (i, id) in _order.indexed)
                  ListTile(
                    key: ValueKey(id),
                    contentPadding: const EdgeInsets.only(left: 4, right: 40),
                    leading: SizedBox(
                      width: 40,
                      child: Text(
                        ordinal(places[id]!),
                        style: d.body(
                          15,
                          color: d.accent,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(
                      id == meId ? 'You' : byId[id]!.displayName,
                      style: d.body(16, weight: FontWeight.w600),
                    ),
                    trailing: i == 0
                        ? Text('Winner', style: d.body(13, color: d.accent))
                        : FilterChip(
                            label: const Text('Tied'),
                            tooltip: 'Knocked out together with the one above',
                            selected: _tiedWithAbove.contains(id),
                            onSelected: (tied) => setState(
                              () => _tiedWithAbove = tied
                                  ? {..._tiedWithAbove, id}
                                  : _tiedWithAbove.difference({id}),
                            ),
                          ),
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
                'Add who played and put them in order to see how ratings '
                'change.',
            rows: ready ? previewRows(mode, meId, widget.players, seats) : null,
          ),
          SendForConfirmationButton(
            error: error,
            saving: saving,
            missing: [if (!ready) 'who played'],
            onPressed: !ready
                ? null
                : () => sendForConfirmation(
                    game: Game.of(mode.type),
                    sentTo: _namesOf(widget.players, _others),
                    rated: _rated,
                    request: (repo) => repo.reportResult(
                      ResultReport(mode: mode, seats: seats, rated: _rated),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
