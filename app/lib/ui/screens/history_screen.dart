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
  const HistoryScreen({super.key, required this.game});

  /// How many results a page holds.
  static const pageSize = 50;

  final Game game;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  /// The member whose results were asked for; null is everyone.
  String? _playerId;

  /// How many results were asked for: a page, and a page more for each
  /// "Load more". Every load, background ones included, fetches this many
  /// from the top, so pages already loaded survive a reload and rows that
  /// changed refresh.
  int _depth = HistoryScreen.pageSize;

  /// What is on screen, to fall back to when a new filter or page fails.
  _History? _shown;

  /// [_depth] results for [_playerId], one extra to learn whether older ones
  /// remain.
  Future<_History> _load(LadderRepository repo) async {
    final playerId = _playerId;
    final depth = _depth;
    try {
      final members = await repo.ladder();
      final tiles = switch (widget.game) {
        Game.chess => [
          for (final m in await repo.matches(
            playerId: playerId,
            limit: depth + 1,
          ))
            MatchTile(match: m) as Widget,
        ],
        Game.backgammon => [
          for (final m in await repo.backgammonMatches(
            playerId: playerId,
            limit: depth + 1,
          ))
            BackgammonMatchTile(match: m) as Widget,
        ],
        Game.swu => [
          for (final m in await repo.swuMatches(
            playerId: playerId,
            limit: depth + 1,
          ))
            SwuMatchTile(match: m) as Widget,
        ],
      };
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
    setState(() {
      _playerId = shown.playerId;
      _depth = shown.depth;
    });
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
                      setState(() {
                        _playerId = id;
                        _depth = HistoryScreen.pageSize;
                      });
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
