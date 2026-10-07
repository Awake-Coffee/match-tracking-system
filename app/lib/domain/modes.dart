import 'backgammon.dart';
import 'elo.dart' as chess_elo;
import 'swu.dart';

/// The games, as `public.match_type` tells them apart.
enum MatchType {
  chess(chess_elo.startingRating),
  backgammon(backgammonStartingRating),
  swu(swuStartingRating);

  const MatchType(this.startingRating);

  /// Rating every member starts with in each of the game's modes.
  final int startingRating;

  List<GameMode> get modes => [
    for (final m in GameMode.values)
      if (m.type == this) m,
  ];

  /// The mode every result was played in before modes existed.
  GameMode get defaultMode => modes.first;
}

/// Who plays whom in a mode. Mirrors `game_modes.format`.
enum ResultFormat {
  /// Two sides of one player.
  duel,

  /// Two sides of two players.
  teams,

  /// Side 1 is the box, alone; side 2 is a team of 2 to 5 sharing a result.
  boxVsTeam,

  /// 3 or 4 sides of one player; a score is how they finished
  /// ([TwinSunsFinish]).
  freeForAll;

  bool get multiplayer => this != duel;
}

/// The ways each game is played at Awake, each with its own ladder. Mirrors
/// `public.game_modes`; [key] is the `mode` column.
enum GameMode {
  standardChess(MatchType.chess, 'standard', 'Standard', 'Classic chess'),
  chess960(
    MatchType.chess,
    'chess960',
    'Chess960',
    'Back ranks shuffled, mirrored for both sides',
  ),
  kingOfTheHill(
    MatchType.chess,
    'king_of_the_hill',
    'King of the Hill',
    'Bring your king to the centre to win',
  ),
  threeCheck(MatchType.chess, 'three_check', 'Three-check', 'Third check wins'),
  crazyhouse(
    MatchType.chess,
    'crazyhouse',
    'Crazyhouse',
    'Captured pieces drop back in on your side',
  ),
  atomic(MatchType.chess, 'atomic', 'Atomic', 'Captures explode'),
  antichess(
    MatchType.chess,
    'antichess',
    'Antichess',
    'Captures are forced; lose every piece to win',
  ),
  horde(MatchType.chess, 'horde', 'Horde', '36 pawns against a full army'),
  racingKings(
    MatchType.chess,
    'racing_kings',
    'Racing Kings',
    'First king to the eighth rank wins',
  ),
  bughouse(
    MatchType.chess,
    'bughouse',
    'Bughouse',
    'Two boards, two teams; captures pass to your partner',
    ResultFormat.teams,
  ),
  standardBackgammon(
    MatchType.backgammon,
    'standard',
    'Standard',
    'Classic backgammon',
  ),
  nackgammon(
    MatchType.backgammon,
    'nackgammon',
    'Nackgammon',
    'Two more back checkers for a longer fight',
  ),
  hypergammon(
    MatchType.backgammon,
    'hypergammon',
    'Hypergammon',
    'Three checkers each',
  ),
  aceyDeucey(
    MatchType.backgammon,
    'acey_deucey',
    'Acey-deucey',
    'Everyone enters from off the board; 1-2 is a bonus roll',
  ),
  tavli(
    MatchType.backgammon,
    'tavli',
    'Tavli',
    'Portes, Plakoto and Fevga in turn',
  ),
  longNardy(
    MatchType.backgammon,
    'long_nardy',
    'Long Nardy',
    'Both race the same way round; no hitting',
  ),
  chouette(
    MatchType.backgammon,
    'chouette',
    'Chouette',
    'One box against a team that shares the result',
    ResultFormat.boxVsTeam,
  ),
  premier(
    MatchType.swu,
    'premier',
    'Premier',
    '1v1, best of one or three, current sets',
  ),
  eternal(
    MatchType.swu,
    'eternal',
    'Eternal',
    '1v1, best of one or three, every set legal',
  ),
  trilogy(MatchType.swu, 'trilogy', 'Trilogy', 'Three decks, each played once'),
  limited(
    MatchType.swu,
    'limited',
    'Limited',
    'Sealed or draft, best of one or three',
  ),
  twinSuns(
    MatchType.swu,
    'twin_suns',
    'Twin Suns',
    '3–4 player free-for-all, two leaders each',
    ResultFormat.freeForAll,
  );

  const GameMode(
    this.type,
    this.key,
    this.label,
    this.rules, [
    this.format = ResultFormat.duel,
  ]);

  final MatchType type;
  final String key;
  final String label;

  /// The mode in one line, for whoever hasn't played it.
  final String rules;
  final ResultFormat format;

  static GameMode of(MatchType type, String key) =>
      values.firstWhere((m) => m.type == type && m.key == key);
}
