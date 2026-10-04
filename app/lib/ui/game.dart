import '../data/ladder_repository.dart';
import '../design/design_spec.dart';
import '../design/designs.dart';
import '../domain/backgammon.dart';
import '../domain/elo.dart' as chess_elo;
import '../domain/models.dart';

/// The games played at Awake. Each is its own interface: its own design,
/// ladder and routes, under one account.
enum Game {
  chess(
    label: 'Chess',
    glyph: '♞',
    routePrefix: '',
    design: roastPawns,
    resultNoun: 'game',
    resultNounPlural: 'games',
    startingRating: chess_elo.startingRating,
  ),
  backgammon(
    label: 'Backgammon',
    glyph: '⚅',
    routePrefix: '/backgammon',
    design: baize,
    resultNoun: 'match',
    resultNounPlural: 'matches',
    startingRating: backgammonStartingRating,
  );

  const Game({
    required this.label,
    required this.glyph,
    required this.routePrefix,
    required this.design,
    required this.resultNoun,
    required this.resultNounPlural,
    required this.startingRating,
  });

  final String label;

  /// The game's mark on its tile in the game picker.
  final String glyph;
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

  static Game at(String location) =>
      location == backgammon.routePrefix ||
          location.startsWith('${backgammon.routePrefix}/')
      ? backgammon
      : chess;

  int ratingOf(Player p) => switch (this) {
    chess => p.rating,
    backgammon => p.backgammon.rating,
  };

  int playedOf(Player p) => switch (this) {
    chess => p.gamesPlayed,
    backgammon => p.backgammon.matchesPlayed,
  };

  /// Every member, best first.
  Future<List<Player>> ladderOf(LadderRepository repo) => switch (this) {
    chess => repo.ladder(),
    backgammon => repo.backgammonLadder(),
  };

  /// Results reported against [meId] that wait for their confirmation.
  Future<int> awaitingCountOf(LadderRepository repo, String meId) async =>
      switch (this) {
        chess => (await repo.matchRequests()).where((r) => r.awaits(meId)),
        backgammon => (await repo.backgammonMatchRequests()).where(
          (r) => r.awaits(meId),
        ),
      }.length;
}
