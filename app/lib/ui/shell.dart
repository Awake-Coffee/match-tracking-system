import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/ladder_repository.dart';
import '../design/design_scope.dart';
import '../design/design_spec.dart';
import '../domain/models.dart';
import 'app_scope.dart';
import 'game.dart';
import 'ladder/ladder_view.dart' show ordinal;
import 'widgets/surface.dart' show SpecBackdrop;

enum _Tab {
  ladder('', 'Ladder', Icons.format_list_numbered),
  record('record', 'Record', Icons.add_circle_outline, Icons.add_circle),
  history('history', 'History', Icons.history),
  you('me', 'You', Icons.person_outline, Icons.person);

  const _Tab(this.page, this.label, this.icon, [IconData? selectedIcon])
    : selectedIcon = selectedIcon ?? icon;

  /// Route within a game, see [Game.path].
  final String page;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  static _Tab at(String page) => switch (page) {
    'record' => record,
    'history' => history,
    'me' || 'settings' => you,
    _ => ladder,
  };
}

/// Below this width the app is a phone app with bottom tabs; above it
/// (laptops, the café's counter tablet) it gets a website-style header.
const _headerMinWidth = 720.0;

/// Navigation around the signed-in screens of [game], with the game picker
/// always in view and content capped to a comfortable reading
/// width on large screens.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.game,
    required this.location,
    required this.child,
  });

  final Game game;
  final String location;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

/// The signed-in member's place in one game, shown on its picker card: in
/// the mode they play most. [rank] is null until they've played.
typedef _Standing = ({
  GameMode mode,
  int rating,
  int? rank,
  int ladderSize,
  int awaitingMe,
});

Future<_Standing> _standingIn(
  Game game,
  LadderRepository repo,
  Player me,
) async {
  final (members, awaitingMe) = await (
    repo.members(),
    game.awaitingCountOf(repo, me.id),
  ).wait;
  final fresh = members.where((p) => p.id == me.id).firstOrNull ?? me;
  final mode = fresh.mostPlayedIn(game.type);
  // Only members who have played are ranked, so "of N" counts them alone.
  final ranked = rankedIn(ladderOf(members, mode), mode);
  final i = ranked.indexWhere((p) => p.id == me.id);
  return (
    mode: mode,
    rating: fresh.standingIn(mode).rating,
    rank: i < 0 ? null : i + 1,
    ladderSize: ranked.length,
    awaitingMe: awaitingMe,
  );
}

class _AppShellState extends State<AppShell> {
  /// The member's standing per game. Results waiting for their confirmation
  /// are badged on that game's Ladder tab, where they're confirmed, and on
  /// the game picker while another game is open.
  // Reloads whenever the repository's revision moves: this client changed
  // data, or the repository heard of someone else's change (Realtime,
  // returning to the app, the fallback poll).
  Future<Map<Game, _Standing>>? _standings;
  int? _revision;

  /// The last standings that loaded: a failed background reload keeps the
  /// badges rather than dropping them until the next success.
  Map<Game, _Standing> _lastStandings = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = context.repo;
    if (_revision == repo.revision) return;
    _revision = repo.revision;
    final me = repo.me;
    final standings = me == null
        ? Future.value(const <Game, _Standing>{})
        : [for (final game in Game.values) _standingIn(game, repo, me)].wait
              .then((s) => Map.fromIterables(Game.values, s));
    _standings = standings.then((s) => _lastStandings = s);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final current = _Tab.at(game.pageOf(widget.location));
    final wide = MediaQuery.sizeOf(context).width >= _headerMinWidth;
    final content = SpecBackdrop(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: widget.child,
        ),
      ),
    );
    return FutureBuilder<Map<Game, _Standing>>(
      future: _standings,
      builder: (context, snap) {
        final standings = snap.data ?? _lastStandings;
        final awaitingMe = standings[game]?.awaitingMe ?? 0;
        final picker = _GamePicker(
          current: game,
          tab: current,
          standings: standings,
          wide: wide,
        );
        if (wide) {
          return Scaffold(
            body: Column(
              children: [
                _WideHeader(
                  game: game,
                  current: current,
                  awaitingMe: awaitingMe,
                  picker: picker,
                ),
                Expanded(child: content),
              ],
            ),
          );
        }
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _PhoneHeader(picker: picker),
                Expanded(child: content),
              ],
            ),
          ),
          bottomNavigationBar: _BottomTabs(
            game: game,
            current: current,
            awaitingMe: awaitingMe,
          ),
        );
      },
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Badge.count(count: count, isLabelVisible: count > 0, child: child);
}

/// The open game's tile and name. Tapping it lays out every game as a card
/// in its own design with the member's standing: a sheet on phones, a menu
/// on wide screens. Switching keeps the same tab.
class _GamePicker extends StatelessWidget {
  const _GamePicker({
    required this.current,
    required this.tab,
    required this.standings,
    required this.wide,
  });

  final Game current;
  final _Tab tab;
  final Map<Game, _Standing> standings;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final awaitingElsewhere = Game.values
        .where((g) => g != current)
        .fold(0, (sum, g) => sum + (standings[g]?.awaitingMe ?? 0));
    final cardsTitle = Text(
      'YOUR LADDERS',
      style: d.body(11, weight: FontWeight.w700, color: d.muted),
    );

    _GameCards cards(VoidCallback close) => _GameCards(
      current: current,
      standings: standings,
      onPick: (game) {
        close();
        if (game != current) context.go(game.path(tab.page));
      },
    );

    // On phones the header shows the short name, so the tooltip names the
    // game in full for mouse users in narrow windows.
    Widget button(VoidCallback onTap) => Tooltip(
      message: wide ? 'Switch game' : 'Switch game (${current.label})',
      child: InkWell(
        onTap: onTap,
        borderRadius: d.borderRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GameTile(game: current),
              const SizedBox(width: 10),
              // The phone header is tight: "Star Wars: Unlimited" at 24pt would
              // be scaled down, so it shows the short name. Screen readers
              // still hear the full one.
              Text(
                wide ? current.label : current.shortLabel,
                style: d.display(24),
                semanticsLabel: current.label,
              ),
              Icon(Icons.expand_more, color: d.muted),
              // Results waiting for the member in the other games.
              if (awaitingElsewhere > 0) Badge.count(count: awaitingElsewhere),
            ],
          ),
        ),
      ),
    );

    if (wide) {
      return MenuAnchor(
        alignmentOffset: const Offset(0, 8),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(d.surface),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(14)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: d.line, width: d.lineWidth),
            ),
          ),
        ),
        menuChildren: [
          SizedBox(
            width: 440,
            child: Builder(
              builder: (menuContext) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  cardsTitle,
                  cards(MenuController.maybeOf(menuContext)!.close),
                ],
              ),
            ),
          ),
        ],
        builder: (context, controller, _) => button(
          () => controller.isOpen ? controller.close() : controller.open(),
        ),
      );
    }

    return button(
      () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: d.surface,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: d.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                cardsTitle,
                cards(() => Navigator.pop(sheetContext)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A game's mark, in its own colors.
class _GameTile extends StatelessWidget {
  const _GameTile({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final d = game.designFor(MediaQuery.platformBrightnessOf(context));
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: d.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: d.accent, width: d.lineWidth),
      ),
      child: Icon(game.mark, color: d.accent, size: 18),
    );
  }
}

/// Every game as a card, two to a row.
class _GameCards extends StatelessWidget {
  const _GameCards({
    required this.current,
    required this.standings,
    required this.onPick,
  });

  final Game current;
  final Map<Game, _Standing> standings;
  final ValueChanged<Game> onPick;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    spacing: 8,
    children: [
      for (var i = 0; i < Game.values.length; i += 2)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              for (final game in Game.values.skip(i).take(2))
                Expanded(
                  child: _GameCard(
                    game: game,
                    standing: standings[game],
                    selected: game == current,
                    onTap: () => onPick(game),
                  ),
                ),
              if (i + 1 == Game.values.length) const Spacer(),
            ],
          ),
        ),
    ],
  );
}

/// One game in its own design: the member's rating, rank and results
/// waiting for them.
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.game,
    required this.standing,
    required this.selected,
    required this.onTap,
  });

  final Game game;
  final _Standing? standing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = game.designFor(MediaQuery.platformBrightnessOf(context));
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: selected ? d.accent : d.line,
        width: selected ? 2 : d.lineWidth,
      ),
    );
    final standing = this.standing;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: d.background,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(game.label, style: d.display(20))),
                    Icon(game.mark, color: d.accent, size: 20),
                  ],
                ),
                if (standing != null)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${standing.rating}',
                          style: d.number(16, weight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: switch (standing.rank) {
                            final rank? =>
                              ' · ${ordinal(rank)} of ${standing.ladderSize}'
                                  '${game.modes.length > 1 ? ' in ${standing.mode.label}' : ''}',
                            null => ' · not ranked yet',
                          },
                        ),
                      ],
                    ),
                    style: d.number(12, color: d.muted),
                  ),
                if ((standing?.awaitingMe ?? 0) > 0)
                  Text(
                    '${standing!.awaitingMe} to confirm',
                    style: d.body(12, weight: FontWeight.w600, color: d.accent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneHeader extends StatelessWidget {
  const _PhoneHeader({required this.picker});

  final Widget picker;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 60,
    child: Padding(
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(
        children: [
          Expanded(
            // Shrinks rather than overflows on narrow phones or large text.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: picker,
            ),
          ),
          const _RefreshButton(),
        ],
      ),
    ),
  );
}

/// Reloads everything on screen. Pull-to-refresh doesn't respond to a
/// mouse, so wide screens and narrow desktop windows need this.
class _RefreshButton extends StatelessWidget {
  const _RefreshButton();

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Refresh',
    onPressed: context.repo.reload,
    icon: Icon(Icons.refresh, color: context.design.muted),
  );
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({
    required this.game,
    required this.current,
    required this.awaitingMe,
  });

  final Game game;
  final _Tab current;
  final int awaitingMe;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: d.background,
        border: Border(
          top: BorderSide(color: d.line, width: d.lineWidth),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (final tab in _Tab.values)
                Expanded(
                  child: _BottomTab(
                    game: game,
                    tab: tab,
                    selected: tab == current,
                    badgeCount: tab == _Tab.ladder ? awaitingMe : 0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomTab extends StatelessWidget {
  const _BottomTab({
    required this.game,
    required this.tab,
    required this.selected,
    required this.badgeCount,
  });

  final Game game;
  final _Tab tab;
  final bool selected;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => context.go(game.path(tab.page)),
        child: d.textTabs ? _textTab(d) : _iconTab(d),
      ),
    );
  }

  /// The word alone, underlined while selected, like a menu board's sections.
  Widget _textTab(DesignSpec d) => Center(
    child: Badge.count(
      count: badgeCount,
      isLabelVisible: badgeCount > 0,
      // Clear of the word's last letter.
      offset: const Offset(14, -6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? d.ink : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          tab.label,
          style: d.display(15, color: selected ? d.ink : d.muted),
        ),
      ),
    ),
  );

  Widget _iconTab(DesignSpec d) => Column(
    children: [
      Container(
        width: 40,
        height: 2,
        color: selected ? d.accent : Colors.transparent,
      ),
      const Spacer(),
      _CountBadge(
        count: badgeCount,
        child: Icon(
          selected ? tab.selectedIcon : tab.icon,
          color: selected ? d.accent : d.muted,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        tab.label,
        style: d.body(
          12,
          weight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? d.ink : d.muted,
        ),
      ),
      const Spacer(),
    ],
  );
}

class _WideHeader extends StatelessWidget {
  const _WideHeader({
    required this.game,
    required this.current,
    required this.awaitingMe,
    required this.picker,
  });

  final Game game;
  final _Tab current;
  final int awaitingMe;
  final Widget picker;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: d.line, width: d.lineWidth),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                Text(d.caps('Awake Ladder'), style: d.display(22)),
                const SizedBox(width: 24),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(fit: BoxFit.scaleDown, child: picker),
                  ),
                ),
                const SizedBox(width: 24),
                for (final tab in [_Tab.ladder, _Tab.history]) ...[
                  _HeaderTab(
                    game: game,
                    tab: tab,
                    selected: tab == current,
                    badgeCount: tab == _Tab.ladder ? awaitingMe : 0,
                  ),
                  const SizedBox(width: 28),
                ],
                const _RefreshButton(),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () => context.go(game.path(_Tab.record.page)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    textStyle: d.button(14),
                  ),
                  child: Text(d.caps('Record ${game.resultNoun}')),
                ),
                const SizedBox(width: 16),
                _YouButton(game: game, selected: current == _Tab.you),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderTab extends StatelessWidget {
  const _HeaderTab({
    required this.game,
    required this.tab,
    required this.selected,
    required this.badgeCount,
  });

  final Game game;
  final _Tab tab;
  final bool selected;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => context.go(game.path(tab.page)),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? d.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: _CountBadge(
            count: badgeCount,
            child: Text(
              tab.label,
              style: d.body(
                15,
                weight: FontWeight.w600,
                color: selected ? d.ink : d.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The signed-in member's initials, opening their profile.
class _YouButton extends StatelessWidget {
  const _YouButton({required this.game, required this.selected});

  final Game game;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final initials = (context.repo.me?.displayName ?? '')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word[0].toUpperCase())
        .join();
    return Tooltip(
      message: _Tab.you.label,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => context.go(game.path(_Tab.you.page)),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: d.highlight,
            border: Border.all(
              color: selected ? d.accent : d.line,
              width: selected ? 2 : d.lineWidth,
            ),
          ),
          child: Text(initials, style: d.body(13, weight: FontWeight.w700)),
        ),
      ),
    );
  }
}
