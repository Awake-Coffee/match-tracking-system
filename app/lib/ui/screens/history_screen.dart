import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/ladder_repository.dart';
import '../../domain/models.dart';
import '../game.dart';
import '../widgets/load_view.dart';
import '../widgets/match_tile.dart';
import '../widgets/surface.dart';

/// What one load showed: the filter and depth it ran for, the members the
/// filter offers, and the results, newest first, with whether older remain.
/// Carrying the filter keeps the list, its wording and the dropdown in step
/// with what actually loaded rather than with what was last asked for.
typedef _History = ({
  String? playerId,
  int depth,
  List<Player> members,
  List<Widget> tiles,
  bool more,
});

/// Every result in the game, newest first, a page at a time, optionally for
/// one member.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.game, this.playerId});

  /// How many results a page holds.
  static const pageSize = 50;

  final Game game;

  /// The member whose results are shown, from the `player` query, so a
  /// filtered history is a link of its own; null is everyone.
  final String? playerId;

  /// The route of [game]'s history for [playerId].
  static String path(Game game, String? playerId) => game.path(
    playerId == null
        ? 'history'
        : 'history?player=${Uri.encodeQueryComponent(playerId)}',
  );

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  /// The member whose results were asked for; null is everyone.
  String? get _playerId => widget.playerId;

  /// How many results were asked for: a page, and a page more for each
  /// "Load more". Every load, background ones included, fetches this many
  /// from the top, so pages already loaded survive a reload and rows that
  /// changed refresh.
  int _depth = HistoryScreen.pageSize;

  /// What is on screen, to fall back to when a new filter or page fails.
  _History? _shown;

  @override
  void didUpdateWidget(HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new member's results start from their first page; going back to
    // what is shown (a failed filter undone) keeps the pages loaded.
    if (widget.playerId != oldWidget.playerId) {
      final shown = _shown;
      _depth = shown != null && shown.playerId == widget.playerId
          ? shown.depth
          : HistoryScreen.pageSize;
    }
  }

  /// [_depth] results for [_playerId], one extra to learn whether older ones
  /// remain.
  Future<_History> _load(LadderRepository repo) async {
    final playerId = _playerId;
    final depth = _depth;
    try {
      final members = await repo.members();
      final memberIds = {for (final p in members) p.id};
      final tiles = [
        for (final r in await repo.results(
          widget.game.type,
          playerId: playerId,
          limit: depth + 1,
        ))
          ResultTile(result: r, memberIds: memberIds),
      ];
      return (
        playerId: playerId,
        depth: depth,
        members: members,
        tiles: tiles.take(depth).toList(),
        more: tiles.length > depth,
      );
    } catch (_) {
      _undo(playerId, depth);
      rethrow;
    }
  }

  /// After a failed load of a new filter or page that is still the latest
  /// asked for, says so and goes back to what is on screen. A failed
  /// background reload of what is already shown stays quiet, as in [LoadView].
  void _undo(String? playerId, int depth) {
    final shown = _shown;
    if (!mounted || shown == null) return;
    if (playerId != _playerId || depth != _depth) return;
    if (playerId == shown.playerId && depth == shown.depth) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          playerId == shown.playerId
              ? 'Couldn\'t load more. Check your connection.'
              : 'Couldn\'t show that player. Check your connection.',
        ),
      ),
    );
    setState(() => _depth = shown.depth);
    // Puts the address back in place, not as a new step in the history.
    if (playerId != shown.playerId) {
      Router.neglect(
        context,
        () => context.go(HistoryScreen.path(widget.game, shown.playerId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return LoadView<_History>(
      load: _load,
      reloadKey: (_playerId, _depth),
      builder: (context, history, _) {
        _shown = history;
        final filtering = history.playerId != _playerId;
        final loadingMore = !filtering && history.depth != _depth;
        final shown = history.tiles;
        final filtered = history.playerId != null;
        return ListView(
          children: [
            ScreenTitle(
              'History',
              subtitle: switch (game) {
                Game.chess => 'Every game played at Awake, newest first.',
                Game.backgammon =>
                  'Every backgammon match at Awake, newest first.',
                Game.swu =>
                  'Every Star Wars: Unlimited match at Awake, newest first.',
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PlayerFilter(
                    // A new menu when the selection is undone, so it snaps
                    // back to what is shown.
                    key: ValueKey(_playerId),
                    members: history.members,
                    selectedId: _playerId,
                    onSelected: (id) {
                      if (id == _playerId) return;
                      context.go(HistoryScreen.path(game, id));
                    },
                  ),
                  // Holds its height so the list doesn't jump when it goes.
                  SizedBox(
                    height: 4,
                    child: filtering ? const LinearProgressIndicator() : null,
                  ),
                ],
              ),
            ),
            if (shown.isEmpty)
              MessageView(
                message: filtered
                    ? 'No ${game.resultNounPlural} for this player yet.'
                    : 'No ${game.resultNounPlural} yet.',
                actionLabel: filtered
                    ? null
                    : 'Record the first ${game.resultNoun}',
                onAction: () => context.go(game.path('record')),
              ),
            for (final (i, tile) in shown.indexed) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: SpecRule(verticalPadding: 0),
                ),
              tile,
            ],
            if (history.more)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: OutlinedButton(
                    onPressed: filtering || loadingMore
                        ? null
                        : () => setState(
                            () =>
                                _depth = history.depth + HistoryScreen.pageSize,
                          ),
                    child: Text(loadingMore ? 'Loading…' : 'Load more'),
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

/// "Everyone" or one member, in the same menu the record forms pick an
/// opponent with.
class _PlayerFilter extends StatelessWidget {
  const _PlayerFilter({
    super.key,
    required this.members,
    required this.selectedId,
    required this.onSelected,
  });

  /// Stands for no filter: a menu entry needs a value to be chosen.
  static const _everyone = '';

  final List<Player> members;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final sorted = [...members]
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    return DropdownMenu<String>(
      initialSelection: selectedId ?? _everyone,
      expandedInsets: EdgeInsets.zero,
      enableFilter: true,
      requestFocusOnTap: true,
      label: const Text('Player'),
      onSelected: (id) => onSelected(id == null || id == _everyone ? null : id),
      dropdownMenuEntries: [
        const DropdownMenuEntry(value: _everyone, label: 'Everyone'),
        for (final p in sorted)
          DropdownMenuEntry(value: p.id, label: p.displayName),
      ],
    );
  }
}
