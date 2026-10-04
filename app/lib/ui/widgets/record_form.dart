import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../app_scope.dart';
import '../game.dart';
import 'surface.dart';

/// Sending a reported result to the opponent, shared by the chess and
/// backgammon record forms.
mixin SendsForConfirmation<T extends StatefulWidget> on State<T> {
  bool saving = false;
  String? error;

  Future<void> sendForConfirmation({
    required Game game,
    required String opponentName,
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
                ? 'Sent to $opponentName. Ratings update once they confirm.'
                : 'Sent to $opponentName. It goes in the history once they '
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

/// Searchable list of everyone but the signed-in member, with their rating
/// in the game being recorded.
class OpponentPicker extends StatelessWidget {
  const OpponentPicker({
    super.key,
    required this.game,
    required this.players,
    required this.meId,
    required this.selectedId,
    required this.onSelected,
  });

  final Game game;
  final List<Player> players;
  final String meId;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final opponents = players.where((p) => p.id != meId).toList()
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    return DropdownMenu<String>(
      initialSelection: selectedId,
      expandedInsets: EdgeInsets.zero,
      enableFilter: true,
      requestFocusOnTap: true,
      hintText: 'Search players',
      onSelected: onSelected,
      dropdownMenuEntries: [
        for (final p in opponents)
          DropdownMenuEntry(
            value: p.id,
            label: p.displayName,
            trailingIcon: Text('${game.ratingOf(p)}'),
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
                Text('Rated', style: d.body(15, weight: FontWeight.w700)),
                Text(
                  rated
                      ? 'Counts toward both ratings.'
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
              'Unrated: neither rating changes.',
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
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: d.body(17, weight: FontWeight.w600),
          ),
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
