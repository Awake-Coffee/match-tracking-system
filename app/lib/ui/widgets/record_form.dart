import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../app_scope.dart';
import '../game.dart';
import 'surface.dart';

/// Sending a reported result to the other players, shared by the record
/// forms.
mixin SendsForConfirmation<T extends StatefulWidget> on State<T> {
  bool saving = false;
  String? error;

  /// [sentTo] names who has to confirm: "Bogdan", "Irina, Matei & Ana".
  Future<void> sendForConfirmation({
    required Game game,
    required String sentTo,
    required bool rated,
    required Future<void> Function(LadderRepository repo) request,
  }) async {
    setState(() {
      saving = true;
      error = null;
    });
    final repo = context.repo;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await request(repo);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            rated
                ? 'Sent to $sentTo. Ratings update once they confirm.'
                : 'Sent to $sentTo. It goes in the history once they '
                      'confirm.',
          ),
        ),
      );
      router.go(game.path());
    } on LadderException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'The ${game.resultNoun} wasn\'t saved. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

/// The member's few most recent opponents as one-tap chips, above a
/// searchable list of everyone but the signed-in member with their rating in
/// the mode being recorded. The café is a group of regulars, so most reports
/// need no typing.
class OpponentPicker extends StatefulWidget {
  const OpponentPicker({
    super.key,
    required this.mode,
    required this.players,
    required this.meId,
    required this.selectedId,
    required this.onSelected,
    this.recentIds = const [],
    this.takenIds = const {},
    this.hintText = 'Search players',
  });

  /// How many recent opponents get a chip.
  static const maxRecent = 4;

  final GameMode mode;
  final List<Player> players;
  final String meId;

  /// Players already picked elsewhere in the form, who aren't offered.
  final Set<String> takenIds;
  final String hintText;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  /// Who the member played or has a pending result with, most recent first.
  final List<String> recentIds;

  @override
  State<OpponentPicker> createState() => _OpponentPickerState();
}

class _OpponentPickerState extends State<OpponentPicker> {
  /// Bumped when a chip picks the opponent, so the menu re-reads the choice.
  /// Also on a tap of the chip already chosen, so text typed since gives way
  /// to the name that will be sent.
  int _epoch = 0;

  void _pickRecent(String id) {
    setState(() => _epoch++);
    widget.onSelected(id);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final opponents =
        widget.players
            .where(
              (p) =>
                  p.id != widget.meId &&
                  (p.id == widget.selectedId ||
                      !widget.takenIds.contains(p.id)),
            )
            .toList()
          ..sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
          );
    final recent = [
      for (final id in widget.recentIds)
        ?opponents.where((p) => p.id == id).firstOrNull,
    ].take(OpponentPicker.maxRecent).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recent.isNotEmpty) ...[
          Text('Recent opponents', style: d.body(13, color: d.muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in recent)
                ChoiceChip(
                  label: Text(p.displayName),
                  selected: p.id == widget.selectedId,
                  onSelected: (_) => _pickRecent(p.id),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        DropdownMenu<String>(
          key: ValueKey(_epoch),
          initialSelection: widget.selectedId,
          expandedInsets: EdgeInsets.zero,
          enableFilter: true,
          requestFocusOnTap: true,
          hintText: widget.hintText,
          onSelected: widget.onSelected,
          dropdownMenuEntries: [
            for (final p in opponents)
              DropdownMenuEntry(
                value: p.id,
                label: p.displayName,
                trailingIcon: Text('${p.standingIn(widget.mode).rating}'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Whether the result counts toward ratings. Off, it's a friendly: confirmed
/// and kept in history, but no rating or record moves.
class RatedSwitch extends StatelessWidget {
  const RatedSwitch({super.key, required this.rated, required this.onChanged});

  final bool rated;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rated', style: d.strong(15)),
                Text(
                  rated
                      ? 'Counts toward everyone\'s rating.'
                      : 'A friendly: kept in history, ratings stay put.',
                  style: d.body(13, color: d.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: rated, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// The [RatingPreview] rows for a result between [seats] in [mode]: how each
/// player of [players] would move, the member ([meId]) first as "You".
List<({String name, int before, int delta})> previewRows(
  GameMode mode,
  String meId,
  List<Player> players,
  List<SeatReport> seats,
) {
  final byId = {for (final p in players) p.id: p};
  final standings = {
    for (final s in seats) s.playerId: byId[s.playerId]!.standingIn(mode),
  };
  final deltas = ratingChanges(mode.type, [
    for (final s in seats)
      (
        playerId: s.playerId,
        side: s.side,
        score: s.score,
        standing: standings[s.playerId]!,
      ),
  ]);
  final ordered = [
    ...seats.where((s) => s.playerId == meId),
    ...seats.where((s) => s.playerId != meId),
  ];
  return [
    for (final s in ordered)
      (
        name: s.playerId == meId ? 'You' : byId[s.playerId]!.displayName,
        before: standings[s.playerId]!.rating,
        delta: deltas[s.playerId]!,
      ),
  ];
}

/// How each player's rating moves, or [emptyHint] until the form says enough.
/// An unrated result moves nothing, so it says that instead.
class RatingPreview extends StatelessWidget {
  const RatingPreview({
    super.key,
    required this.rows,
    required this.emptyHint,
    this.rated = true,
  });

  final List<({String name, int before, int delta})>? rows;
  final String emptyHint;
  final bool rated;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final rows = this.rows;
    return SpecSurface(
      child: !rated
          ? Text(
              'Unrated: no rating changes.',
              style: d.body(15, color: d.muted),
            )
          : rows == null
          ? Text(emptyHint, style: d.body(15, color: d.muted))
          : Column(
              children: [
                for (final (i, r) in rows.indexed) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _PreviewRow(name: r.name, before: r.before, delta: r.delta),
                ],
              ],
            ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.name,
    required this.before,
    required this.delta,
  });

  final String name;
  final int before;
  final int delta;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final nameText = Text(
      name,
      overflow: TextOverflow.ellipsis,
      style: d.strong(17),
    );
    return Row(
      crossAxisAlignment: d.leaders
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.center,
      children: [
        Expanded(
          child: d.leaders
              ? LeaderRow(lead: nameText, color: d.muted)
              : nameText,
        ),
        Text('$before to ', style: d.number(16, color: d.muted)),
        Text('${before + delta}', style: d.number(18, weight: FontWeight.w700)),
        const SizedBox(width: 12),
        SizedBox(
          width: 44,
          child: Align(
            alignment: Alignment.centerRight,
            child: DeltaText(delta, size: 16),
          ),
        ),
      ],
    );
  }
}

/// The form's error, if any, above its send button, and under a disabled one
/// what is still missing, so it never looks broken.
class SendForConfirmationButton extends StatelessWidget {
  const SendForConfirmationButton({
    super.key,
    required this.error,
    required this.saving,
    required this.onPressed,
    this.missing = const [],
  });

  final String? error;
  final bool saving;

  /// Null while the form is incomplete.
  final VoidCallback? onPressed;

  /// What the form still needs, each with its article ("an opponent"), in
  /// form order. Shown as "Pick an opponent and a time control".
  final List<String> missing;

  /// "a", "a and b", "a, b and c".
  static String _list(List<String> items) => items.length < 2
      ? items.join()
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error case final error?) ...[
          const SizedBox(height: 16),
          Text(
            error,
            style: d.body(15, color: d.loss, weight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: saving ? null : onPressed,
          child: saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send for confirmation'),
        ),
        if (onPressed == null && !saving && missing.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Pick ${_list(missing)}',
            textAlign: TextAlign.center,
            style: d.body(14, color: d.muted),
          ),
        ],
      ],
    );
  }
}
