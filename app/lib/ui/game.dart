import 'package:flutter/widgets.dart';

import '../data/ladder_repository.dart';
import '../design/design_spec.dart';
import '../design/designs.dart';
import '../domain/backgammon.dart';
import '../domain/elo.dart' as chess_elo;
import '../domain/models.dart';
import '../domain/swu.dart';

/// Noto Sans Symbols 2 cut to the three game marks, each recentred in its em
/// box so it sits dead centre whatever platform renders it.
const _marksFont = 'GameMarks';

/// The games played at Awake. Each is its own interface: its own design,
/// ladder and routes, under one account.
enum Game {
  chess(
    label: 'Chess',
    mark: IconData(0x265E, fontFamily: _marksFont),
    routePrefix: '',
    design: roastPawns,
    resultNoun: 'game',
    resultNounPlural: 'games',
    startingRating: chess_elo.startingRating,
  ),
  backgammon(
    label: 'Backgammon',
    mark: IconData(0x2685, fontFamily: _marksFont),
    routePrefix: '/backgammon',
    design: baize,
    resultNoun: 'match',
    resultNounPlural: 'matches',
    startingRating: backgammonStartingRating,
  ),
  swu(
    label: 'Star Wars: Unlimited',
    mark: IconData(0x2726, fontFamily: _marksFont),
    routePrefix: '/swu',
    design: holotable,
    resultNoun: 'match',
    resultNounPlural: 'matches',
    startingRating: swuStartingRating,
  );

  const Game({
    required this.label,
    required this.mark,
    required this.routePrefix,
    required this.design,
    required this.resultNoun,
    required this.resultNounPlural,
    required this.startingRating,
  });

  final String label;

  /// The game's mark on its tile in the game picker.
  final IconData mark;
  final String routePrefix;
  final DesignSpec design;

  /// What one result is called: a chess "game", a backgammon "match".
  final String resultNoun;
  final String resultNounPlural;
  final int startingRating;

  /// The route of [page] (`''` for the ladder, `'record'`, `'players/ID'`,
  /// ...) in this game.
  String path([String page = '']) => page.isEmpty
      ? (routePrefix.isEmpty ? '/' : routePrefix)
      : '$routePrefix/$page';

  /// [location] without this game's prefix, e.g. 'record' or ''.
  String pageOf(String location) =>
      location.substring(routePrefix.length).replaceFirst(RegExp('^/'), '');

  static Game at(String location) => values.firstWhere(
    (g) =>
        g.routePrefix.isNotEmpty &&
        (location == g.routePrefix || location.startsWith('${g.routePrefix}/')),
    orElse: () => chess,
  );

  int ratingOf(Player p) => switch (this) {
    chess => p.rating,
    backgammon => p.backgammon.rating,
    swu => p.swu.rating,
  };

  int playedOf(Player p) => switch (this) {
    chess => p.gamesPlayed,
    backgammon => p.backgammon.matchesPlayed,
    swu => p.swu.matchesPlayed,
  };

  /// Every member, best first.
  Future<List<Player>> ladderOf(LadderRepository repo) => switch (this) {
    chess => repo.ladder(),
    backgammon => repo.backgammonLadder(),
    swu => repo.swuLadder(),
  };

  /// Results reported against [meId] that wait for their confirmation.
  Future<int> awaitingCountOf(LadderRepository repo, String meId) async =>
      switch (this) {
        chess => (await repo.matchRequests()).where((r) => r.awaits(meId)),
        backgammon => (await repo.backgammonMatchRequests()).where(
          (r) => r.awaits(meId),
        ),
        swu => (await repo.swuMatchRequests()).where((r) => r.awaits(meId)),
      }.length;
}
