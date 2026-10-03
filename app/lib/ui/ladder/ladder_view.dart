import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../../domain/models.dart';

/// Data every ladder style receives.
class LadderData {
  const LadderData({
    required this.players,
    required this.meId,
    required this.onOpen,
    required this.now,
  });

  /// Sorted, highest rating first.
  final List<Player> players;
  final String? meId;
  final void Function(Player) onOpen;
  final DateTime now;

  int get gamesLogged => players.fold(0, (sum, p) => sum + p.gamesPlayed) ~/ 2;

  /// "You're 3rd of 8 with 1016." or null when signed out.
  String? get summary {
    final i = players.indexWhere((p) => p.id == meId);
    if (i < 0) return null;
    final me = players[i];
    if (me.gamesPlayed == 0) {
      return 'You start at ${me.rating}. Record a game to climb.';
    }
    return 'You\'re ${ordinal(i + 1)} of ${players.length} with ${me.rating}.';
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

String record(Player p) => '${p.wins}-${p.losses}-${p.draws}';

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
          '${isMe ? ' (you)' : ''}, rating ${player.rating}',
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
