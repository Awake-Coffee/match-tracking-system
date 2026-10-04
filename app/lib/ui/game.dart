import 'package:flutter/widgets.dart';

import '../data/ladder_repository.dart';
import '../design/design_spec.dart';
import '../design/designs.dart';
import '../domain/models.dart';

/// Noto Sans Symbols 2 cut to the three game marks, each recentred in its em
/// box so it sits dead centre whatever platform renders it.
const _marksFont = 'GameMarks';

/// The games played at Awake. Each is its own interface: its own design,
/// ladder and routes, under one account.
enum Game {
  chess(
    type: MatchType.chess,
    label: 'Chess',
    shortLabel: 'Chess',
    mark: IconData(0x265E, fontFamily: _marksFont),
    routePrefix: '',
    design: counterDark,
    lightDesign: counterLight,
    resultNoun: 'game',
    resultNounPlural: 'games',
  ),
  backgammon(
    type: MatchType.backgammon,
    label: 'Backgammon',
    shortLabel: 'Backgammon',
    mark: IconData(0x2685, fontFamily: _marksFont),
    routePrefix: '/backgammon',
    design: baize,
    resultNoun: 'match',
    resultNounPlural: 'matches',
  ),
  swu(
    type: MatchType.swu,
    label: 'Star Wars: Unlimited',
    shortLabel: 'SWU',
    mark: IconData(0x2726, fontFamily: _marksFont),
    routePrefix: '/swu',
    design: holotable,
    resultNoun: 'match',
    resultNounPlural: 'matches',
  );

  const Game({
    required this.type,
    required this.label,
    required this.shortLabel,
    required this.mark,
    required this.routePrefix,
    required this.design,
    this.lightDesign,
    required this.resultNoun,
    required this.resultNounPlural,
  });

  final MatchType type;
  final String label;

  /// [label] where space is tight (the phone header), so a long name needn't
  /// be scaled down to fit. Anything that announces the game uses [label].
  final String shortLabel;

  /// The game's mark on its tile in the game picker.
  final IconData mark;
  final String routePrefix;

  /// The game's design, and its only one unless it has a [lightDesign].
  final DesignSpec design;

  /// The design under the system's light setting, for a game whose look
  /// follows it. Read both through [designFor].
  final DesignSpec? lightDesign;

  /// The design to show while the system is set to [brightness].
  DesignSpec designFor(Brightness brightness) =>
      brightness == Brightness.light ? lightDesign ?? design : design;

  /// What one result is called: a chess "game", a backgammon "match".
  final String resultNoun;
  final String resultNounPlural;

  int get startingRating => type.startingRating;

  /// Each mode has its own ladder; the first is the game as it was always
  /// played here.
  List<GameMode> get modes => type.modes;

  /// The route of [page] (`''` for the ladder, `'record'`, `'players/ID'`,
  /// ...) in this game.
  String path([String page = '']) => page.isEmpty
      ? (routePrefix.isEmpty ? '/' : routePrefix)
      : '$routePrefix/$page';

  /// [location] without this game's prefix, e.g. 'record' or ''.
  String pageOf(String location) =>
      location.substring(routePrefix.length).replaceFirst(RegExp('^/'), '');

  static Game of(MatchType type) => values.firstWhere((g) => g.type == type);

  static Game at(String location) => values.firstWhere(
    (g) =>
        g.routePrefix.isNotEmpty &&
        (location == g.routePrefix || location.startsWith('${g.routePrefix}/')),
    orElse: () => chess,
  );

  /// The members [meId] has played or has a pending result with in this game,
  /// most recent first, each once. A shortcut for the record form, so a failed
  /// load reads as no history rather than blocking it. [ownResults] are the
  /// member's own results when the caller already fetches them.
  Future<List<String>> recentOpponentsOf(
    LadderRepository repo,
    String meId, {
    Future<List<GameResult>>? ownResults,
  }) async {
    try {
      return distinctNewestFirst([
        for (final r
            in await (ownResults ?? repo.results(type, playerId: meId)))
          for (final s in r.seats)
            if (s.playerId != meId) (id: s.playerId, at: r.playedAt),
        for (final r in await repo.requests())
          if (r.mode.type == type &&
              r.involves(meId) &&
              r.status == RequestStatus.pending)
            for (final s in r.seats)
              if (s.playerId != meId) (id: s.playerId, at: r.createdAt),
      ]);
    } catch (_) {
      return const [];
    }
  }

  /// Results in this game that wait for [meId] to confirm them.
  Future<int> awaitingCountOf(LadderRepository repo, String meId) async =>
      (await repo.requests())
          .where((r) => r.mode.type == type && r.awaits(meId))
          .length;
}

/// [word] starting a sentence: "game" → "Game".
String capitalized(String word) =>
    '${word[0].toUpperCase()}${word.substring(1)}';

/// The members of [ladder] who have played [mode], in ladder order. Only they
/// hold a rank: an unplayed member merely sits at the starting rating.
List<Player> rankedIn(List<Player> ladder, GameMode mode) => [
  for (final p in ladder)
    if (p.standingIn(mode).played > 0) p,
];

/// The ids of [games] by time, newest first, each once. Ties keep their given
/// order, so confirmed and pending games merge predictably.
List<String> distinctNewestFirst(Iterable<({String id, DateTime at})> games) {
  final indexed = games.indexed.toList()
    ..sort((a, b) {
      final byTime = b.$2.at.compareTo(a.$2.at);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  return {for (final (_, g) in indexed) g.id}.toList();
}
