import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/ladder_repository.dart';
import '../../domain/models.dart';
import '../app_scope.dart';
import '../game.dart';
import '../widgets/load_view.dart';
import '../widgets/match_tile.dart';
import '../widgets/surface.dart';

/// One result on the page: its tile, and when it was played for the cursor.
typedef _Entry = ({Widget tile, DateTime playedAt});

/// A page of results, newest first, and whether older ones remain.
typedef _Page = ({List<_Entry> entries, bool more});

/// The first page, and the members the filter offers.
typedef _History = ({List<Player> members, _Page first});

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
  /// The member whose results show; null is everyone.
  String? _playerId;

  /// The first page the pages below were loaded after. A reload brings a new
  /// one and drops them, since the list may have shifted underneath.
  _History? _base;

  /// Pages loaded with "Load more", after [_base]'s first page.
  final _more = <_Entry>[];

  /// Whether older results remain after [_more]; null until one loads.
  bool? _moreRemain;
  bool _loadingMore = false;

  /// One page of results played before [before], one extra to learn whether
  /// older ones remain.
  Future<_Page> _fetch(LadderRepository repo, {DateTime? before}) async {
    const size = HistoryScreen.pageSize;
    final id = _playerId;
    final rows = switch (widget.game) {
      Game.chess => [
        for (final m in await repo.matches(
          playerId: id,
          limit: size + 1,
          before: before,
        ))
          (tile: MatchTile(match: m) as Widget, playedAt: m.playedAt),
      ],
      Game.backgammon => [
        for (final m in await repo.backgammonMatches(
          playerId: id,
          limit: size + 1,
          before: before,
        ))
          (tile: BackgammonMatchTile(match: m) as Widget, playedAt: m.playedAt),
      ],
      Game.swu => [
        for (final m in await repo.swuMatches(
          playerId: id,
          limit: size + 1,
          before: before,
        ))
          (tile: SwuMatchTile(match: m) as Widget, playedAt: m.playedAt),
      ],
    };
    return (entries: rows.take(size).toList(), more: rows.length > size);
  }

  Future<_History> _load(LadderRepository repo) async {
    final members = await repo.ladder();
    return (members: members, first: await _fetch(repo));
  }

  Future<void> _loadMore(_History base, List<_Entry> shown) async {
    final repo = context.repo;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(repo, before: shown.last.playedAt);
      // A reload or a new filter while this was in flight made it stale.
      if (!mounted || !identical(base, _base)) return;
      setState(() {
        _more.addAll(page.entries);
        _moreRemain = page.more;
      });
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t load more. Check your connection.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return LoadView<_History>(
      load: _load,
      builder: (context, history, reload) {
        if (!identical(history, _base)) {
          _base = history;
          _more.clear();
          _moreRemain = null;
        }
        final shown = [...history.first.entries, ..._more];
        final remain = _moreRemain ?? history.first.more;
        final filtered = _playerId != null;
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
              child: _PlayerFilter(
                members: history.members,
                selectedId: _playerId,
                onSelected: (id) {
                  setState(() => _playerId = id);
                  reload();
                },
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
            for (final (i, entry) in shown.indexed) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: SpecRule(verticalPadding: 0),
                ),
              entry.tile,
            ],
            if (remain)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: OutlinedButton(
                    onPressed: _loadingMore
                        ? null
                        : () => _loadMore(history, shown),
                    child: Text(_loadingMore ? 'Loading…' : 'Load more'),
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
