import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../../domain/models.dart';
import '../game.dart';
import '../widgets/avatar.dart';

/// Data every ladder style receives.
class LadderData {
  const LadderData({
    required this.mode,
    required this.players,
    required this.meId,
    required this.onOpen,
    required this.now,
  });

  /// Whose ladder this is: one mode of a game.
  final GameMode mode;

  /// Every member, sorted with the highest rating in [mode] first.
  final List<Player> players;
  final String? meId;
  final void Function(Player) onOpen;
  final DateTime now;

  Game get game => Game.of(mode.type);

  Standing standingOf(Player p) => p.standingIn(mode);

  /// Members who have played [mode], best first. Only they get a rank, a
  /// line on the board, a point or a stop on the route.
  List<Player> get ranked => rankedIn(players, mode);

  /// Members with no results in [mode] yet, listed apart and unranked.
  List<Player> get unplayed => [
    for (final p in players)
      if (standingOf(p).played == 0) p,
  ];

  /// "You're 3rd of 8 with 1016." or null when signed out. The 8 counts
  /// ranked members only.
  String? get summary {
    final me = players.where((p) => p.id == meId).firstOrNull;
    if (me == null) return null;
    final rating = standingOf(me).rating;
    if (standingOf(me).played == 0) {
      return 'You start at $rating. Record a ${game.resultNoun} to climb.';
    }
    final ranked = this.ranked;
    final place = ranked.indexWhere((p) => p.id == me.id) + 1;
    return 'You\'re ${ordinal(place)} of ${ranked.length} with $rating.';
  }

  /// "10 to pass Irina": the points that lift [meId] past the ranked member
  /// directly above, or null for first place, a member who has not played and
  /// a signed-out viewer. One more than the gap, because a tie does not pass.
  String? get chase {
    final ranked = this.ranked;
    final i = ranked.indexWhere((p) => p.id == meId);
    if (i < 1) return null;
    final above = ranked[i - 1];
    final points = standingOf(above).rating - standingOf(ranked[i]).rating + 1;
    return '$points to pass ${above.displayName}';
  }
}

String ordinal(int n) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

/// The members who have not played yet, below the ranked ladder: muted, with
/// no rank number, still opening their profile. Empty when everyone has played.
class UnplayedGroup extends StatelessWidget {
  const UnplayedGroup({super.key, required this.data});

  final LadderData data;

  @override
  Widget build(BuildContext context) {
    final unplayed = data.unplayed;
    if (unplayed.isEmpty) return const SizedBox.shrink();
    final d = context.design;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 4),
          child: Text('Not yet played', style: d.body(13, color: d.muted)),
        ),
        for (final p in unplayed)
          LadderRowTap(
            player: p,
            data: data,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: p.id == data.meId ? d.highlight : null,
                border: Border(bottom: BorderSide(color: d.surface)),
              ),
              child: Row(
                children: [
                  Avatar(face: p.face, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p.id == data.meId
                          ? '${p.displayName} (you)'
                          : p.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: d.body(15, color: d.muted),
                    ),
                  ),
                  Text(
                    '${data.standingOf(p).rating}',
                    style: d.number(16, color: d.muted),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Tap target wrapper shared by ladder rows: the whole row opens the profile
/// and gets a visible focus highlight for keyboard users.
class LadderRowTap extends StatelessWidget {
  const LadderRowTap({
    super.key,
    required this.player,
    required this.data,
    required this.child,
    this.rank,
  });

  final Player player;
  final LadderData data;
  final Widget child;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final isMe = player.id == data.meId;
    return Semantics(
      button: true,
      label:
          '${rank != null ? '${ordinal(rank!)}, ' : ''}${player.displayName}'
          '${isMe ? ' (you)' : ''}, rating ${data.standingOf(player).rating}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => data.onOpen(player),
        borderRadius: d.borderRadius,
        focusColor: d.accent.withValues(alpha: 0.3),
        child: child,
      ),
    );
  }
}
