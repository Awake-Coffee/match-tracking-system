import 'backgammon.dart';
import 'elo.dart';
import 'swu.dart';

enum PieceColor { white, black }

/// A result from one player's point of view.
enum Outcome {
  win(1),
  draw(0.5),
  loss(0);

  const Outcome(this.score);
  final double score;
}

/// How a game ended, from the board's point of view (as stored).
enum MatchResult { white, black, draw }

class Player implements FideRated {
  const Player({
    required this.id,
    required this.displayName,
    required this.rating,
    required this.peakRating,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.draws,
    this.backgammon = const BackgammonStats(),
    this.swu = const SwuStats(),
  });

  factory Player.fromRow(Map<String, dynamic> row) => Player(
    id: row['id'] as String,
    displayName: row['display_name'] as String,
    rating: row['rating'] as int,
    peakRating: row['peak_rating'] as int,
    gamesPlayed: row['games_played'] as int,
    wins: row['wins'] as int,
    losses: row['losses'] as int,
    draws: row['draws'] as int,
    backgammon: BackgammonStats.fromRow(row),
    swu: SwuStats.fromRow(row),
  );

  final String id;
  final String displayName;
  @override
  final int rating;
  @override
  final int peakRating;
  @override
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int draws;

  /// The member's separate backgammon rating and record.
  final BackgammonStats backgammon;

  /// The member's separate Star Wars: Unlimited rating and record.
  final SwuStats swu;

  Player copyWith({
    String? displayName,
    int? rating,
    int? peakRating,
    int? gamesPlayed,
    int? wins,
    int? losses,
    int? draws,
    BackgammonStats? backgammon,
    SwuStats? swu,
  }) => Player(
    id: id,
    displayName: displayName ?? this.displayName,
    rating: rating ?? this.rating,
    peakRating: peakRating ?? this.peakRating,
    gamesPlayed: gamesPlayed ?? this.gamesPlayed,
    wins: wins ?? this.wins,
    losses: losses ?? this.losses,
    draws: draws ?? this.draws,
    backgammon: backgammon ?? this.backgammon,
    swu: swu ?? this.swu,
  );
}

/// The presets of a DGT 2500 clock that suit a chess game, keyed by the
/// clock's option number so players pick exactly what they set on the clock.
enum TimeControl {
  sudden5(1, 'Sudden death 5 min'),
  sudden25(2, 'Sudden death 25 min'),
  sudden60(3, 'Sudden death 60 min'),
  classical120plus30(4, '120 min/40 + 30 min'),
  classical120plus60(5, '120 min/40 + 60 min'),
  classical120plus60plus30(6, '120 min/40 + 60 min/20 + 30 min'),
  armageddon(7, 'Armageddon 5 vs 4 min'),
  suddenCustom(8, 'Sudden death custom', custom: true),
  fischer3plus2(9, 'Fischer 3 min + 2 s'),
  fischer5plus3(10, 'Fischer 5 min + 3 s'),
  fischer10plus10(11, 'Fischer 10 min + 10 s'),
  fischer15plus5(12, 'Fischer 15 min + 5 s'),
  fischer15plus10(13, 'Fischer 15 min + 10 s'),
  fischer25plus10(14, 'Fischer 25 min + 10 s'),
  fischer90plus30(15, 'Fischer 90 min + 30 s'),
  fischer90per40plus30(16, 'Fischer 90 min/40 + 30 min + 30 s'),
  fischer100per40plus50(17, 'Fischer 100 min/40 + 50 min + 30 s'),
  fischer100per40plus50plus15(18, 'Fischer 100/40 + 50/20 + 15 min + 30 s'),
  fischer120per40plus60plus15(19, 'Fischer 120/40 + 60/20 + 15 min + 30 s'),
  fischerArmageddon(20, 'Fischer Armageddon 5 vs 4 min + 2 s'),
  fischerCustom(21, 'Fischer custom', custom: true, extraName: 'Increment'),
  bronstein90plus5(22, 'Bronstein 90 min + 5 s'),
  bronsteinCustom(23, 'Bronstein custom', custom: true, extraName: 'Delay'),
  usDelay25plus5(24, 'US delay 25 min + 5 s'),
  usDelayCustom(25, 'US delay custom', custom: true, extraName: 'Delay'),
  byoYomi60(26, 'Byo-yomi 60 min + 3 × 20 s'),
  byoYomiCustom(27, 'Byo-yomi custom', custom: true, extraName: 'Period'),
  canadianByoYomi60(28, 'Canadian byo-yomi 60 min + 5 min'),
  canadianByoYomiCustom(
    29,
    'Canadian byo-yomi custom',
    custom: true,
    extraName: 'Byo-yomi',
  ),
  hourglass1(32, 'Hourglass 1 min'),
  hourglassCustom(33, 'Hourglass custom', custom: true);

  const TimeControl(
    this.dgtOption,
    this.label, {
    this.custom = false,
    this.extraName,
  });

  /// The option number shown on the clock (and stored in the database).
  final int dgtOption;
  final String label;

  /// A manual-setting preset: players enter the base time they set.
  final bool custom;

  /// What the extra seconds mean for a custom preset that has them
  /// (increment, delay, byo-yomi); null when there's only a base time.
  final String? extraName;

  static TimeControl? fromDgtOption(int? option) =>
      values.where((t) => t.dgtOption == option).firstOrNull;
}

/// The time control a game was played on: a preset, plus the time the
/// players set when the preset is a custom one.
class ClockSetting {
  const ClockSetting(
    this.preset, {
    this.customBaseMinutes,
    this.customExtraSeconds,
  });

  static ClockSetting? fromRow(Map<String, dynamic> row) {
    final preset = TimeControl.fromDgtOption(row['dgt_option'] as int?);
    return preset == null
        ? null
        : ClockSetting(
            preset,
            customBaseMinutes: row['custom_base_minutes'] as int?,
            customExtraSeconds: row['custom_extra_seconds'] as int?,
          );
  }

  final TimeControl preset;
  final int? customBaseMinutes;
  final int? customExtraSeconds;

  /// Whether the custom values are exactly the ones the preset needs.
  bool get isComplete => preset.custom
      ? customBaseMinutes != null &&
            customBaseMinutes! > 0 &&
            (customExtraSeconds != null) == (preset.extraName != null)
      : customBaseMinutes == null && customExtraSeconds == null;

  String get label {
    final base = customBaseMinutes;
    if (!preset.custom || base == null) return preset.label;
    final method = preset.label.replaceFirst(' custom', '');
    final extra = customExtraSeconds;
    return extra == null ? '$method $base min' : '$method $base min + $extra s';
  }
}

/// Who had which color and how the game ended: shared by rated games and
/// games still waiting for the opponent to confirm.
abstract class GameReport {
  const GameReport({
    required this.whiteId,
    required this.blackId,
    required this.whiteName,
    required this.blackName,
    required this.result,
    required this.clock,
    this.rated = true,
  });

  final String whiteId;
  final String blackId;
  final String whiteName;
  final String blackName;
  final MatchResult result;

  /// Null for games recorded before time controls were tracked.
  final ClockSetting? clock;

  /// False for a game that's kept in history but moves no rating.
  final bool rated;

  bool involves(String playerId) => playerId == whiteId || playerId == blackId;

  PieceColor colorOf(String playerId) =>
      playerId == whiteId ? PieceColor.white : PieceColor.black;

  String opponentName(String playerId) =>
      playerId == whiteId ? blackName : whiteName;

  String opponentId(String playerId) => playerId == whiteId ? blackId : whiteId;

  Outcome outcomeFor(String playerId) {
    if (result == MatchResult.draw) return Outcome.draw;
    final won = (result == MatchResult.white) == (playerId == whiteId);
    return won ? Outcome.win : Outcome.loss;
  }

  String? get winnerId => switch (result) {
    MatchResult.white => whiteId,
    MatchResult.black => blackId,
    MatchResult.draw => null,
  };

  String? get winnerName => switch (result) {
    MatchResult.white => whiteName,
    MatchResult.black => blackName,
    MatchResult.draw => null,
  };

  String? get loserName => switch (result) {
    MatchResult.white => blackName,
    MatchResult.black => whiteName,
    MatchResult.draw => null,
  };
}

/// A player's display name embedded by a `side:profiles!...` select.
String joinedName(Map<String, dynamic> row, String side) =>
    (row[side] as Map?)?['display_name'] as String? ?? '';

/// A confirmed chess game, backgammon or SWU match, as a player's rating line
/// sees it. Unrated ones change nothing, so their after equals their before.
abstract interface class RatedGame {
  bool get rated;
  int ratingBeforeFor(String playerId);
  int ratingAfterFor(String playerId);
}

/// A confirmed game, rated unless [rated] is false.
class ChessMatch extends GameReport implements RatedGame {
  const ChessMatch({
    required this.id,
    required super.whiteId,
    required super.blackId,
    required super.whiteName,
    required super.blackName,
    required super.result,
    super.clock,
    super.rated,
    required this.whiteRatingBefore,
    required this.blackRatingBefore,
    required this.whiteRatingDelta,
    required this.blackRatingDelta,
    required this.playedAt,
  });

  factory ChessMatch.fromRow(Map<String, dynamic> row) => ChessMatch(
    id: row['id'] as int,
    whiteId: row['white_id'] as String,
    blackId: row['black_id'] as String,
    whiteName: joinedName(row, 'white'),
    blackName: joinedName(row, 'black'),
    result: MatchResult.values.byName(row['result'] as String),
    clock: ClockSetting.fromRow(row),
    rated: row['rated'] as bool,
    whiteRatingBefore: row['white_rating_before'] as int,
    blackRatingBefore: row['black_rating_before'] as int,
    whiteRatingDelta: row['white_rating_delta'] as int,
    blackRatingDelta: row['black_rating_delta'] as int,
    playedAt: DateTime.parse(row['played_at'] as String).toLocal(),
  );

  final int id;
  final int whiteRatingBefore;
  final int blackRatingBefore;
  final int whiteRatingDelta;
  final int blackRatingDelta;
  final DateTime playedAt;

  int deltaFor(String playerId) =>
      playerId == whiteId ? whiteRatingDelta : blackRatingDelta;

  @override
  int ratingBeforeFor(String playerId) =>
      playerId == whiteId ? whiteRatingBefore : blackRatingBefore;

  @override
  int ratingAfterFor(String playerId) =>
      ratingBeforeFor(playerId) + deltaFor(playerId);
}

/// A reported game that only counts once the other player confirms it.
class MatchRequest extends GameReport {
  const MatchRequest({
    required this.id,
    required super.whiteId,
    required super.blackId,
    required super.whiteName,
    required super.blackName,
    required super.result,
    required ClockSetting super.clock,
    super.rated,
    required this.requestedBy,
    required this.createdAt,
  });

  factory MatchRequest.fromRow(Map<String, dynamic> row) => MatchRequest(
    id: row['id'] as int,
    whiteId: row['white_id'] as String,
    blackId: row['black_id'] as String,
    whiteName: joinedName(row, 'white'),
    blackName: joinedName(row, 'black'),
    result: MatchResult.values.byName(row['result'] as String),
    clock: ClockSetting.fromRow(row)!,
    rated: row['rated'] as bool,
    requestedBy: row['requested_by'] as String,
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
  );

  final int id;
  final String requestedBy;
  final DateTime createdAt;

  @override
  ClockSetting get clock => super.clock!;

  /// Whether [playerId] is the one who has to confirm or decline.
  bool awaits(String playerId) => involves(playerId) && playerId != requestedBy;
}

/// The board result implied by one player's color and outcome.
MatchResult resultFor(PieceColor myColor, Outcome myOutcome) =>
    switch (myOutcome) {
      Outcome.draw => MatchResult.draw,
      Outcome.win =>
        myColor == PieceColor.white ? MatchResult.white : MatchResult.black,
      Outcome.loss =>
        myColor == PieceColor.white ? MatchResult.black : MatchResult.white,
    };

/// The rating change a game would cause, before it's saved.
class MatchPreview {
  MatchPreview({
    required this.me,
    required this.opponent,
    required this.outcome,
  }) : myDelta = fideRatingChange(me, opponent, outcome.score),
       opponentDelta = fideRatingChange(opponent, me, 1 - outcome.score);

  final Player me;
  final Player opponent;
  final Outcome outcome;
  final int myDelta;
  final int opponentDelta;

  int get myRatingAfter => me.rating + myDelta;
  int get opponentRatingAfter => opponent.rating + opponentDelta;
}

/// A player's rating after each game, oldest first, from [start] when they
/// haven't played.
List<int> ratingHistory(
  String playerId,
  List<RatedGame> matchesOldestFirst, {
  int start = startingRating,
}) {
  final points = <int>[
    matchesOldestFirst.isEmpty
        ? start
        : matchesOldestFirst.first.ratingBeforeFor(playerId),
  ];
  for (final m in matchesOldestFirst) {
    points.add(m.ratingAfterFor(playerId));
  }
  return points;
}
