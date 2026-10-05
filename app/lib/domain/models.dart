import 'dart:math' as math;

import 'backgammon.dart';
import 'elo.dart';
import 'modes.dart';
import 'swu.dart';

export 'modes.dart';

enum PieceColor { white, black }

/// A result from one player's point of view.
enum Outcome {
  win(1),
  draw(0.5),
  loss(0);

  const Outcome(this.score);
  final double score;

  static Outcome of(num myScore, num opponentScore) =>
      switch (myScore.compareTo(opponentScore)) {
        > 0 => win,
        < 0 => loss,
        _ => draw,
      };
}

/// A member's rating and record in one mode: their `ratings` row.
class Standing implements FideRated {
  const Standing({
    required this.rating,
    required this.peakRating,
    this.played = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.experience = 0,
  });

  /// Where every member starts in a mode of [type], before their first
  /// result there.
  Standing.start(MatchType type)
    : this(rating: type.startingRating, peakRating: type.startingRating);

  factory Standing.fromRow(Map<String, dynamic> row) => Standing(
    rating: row['rating'] as int,
    peakRating: row['peak_rating'] as int,
    played: row['played'] as int,
    wins: row['wins'] as int,
    losses: row['losses'] as int,
    draws: row['draws'] as int,
    experience: row['experience'] as int,
  );

  @override
  final int rating;
  @override
  final int peakRating;
  final int played;
  final int wins;
  final int losses;
  final int draws;

  /// FIBS experience (backgammon only): the summed lengths of every match.
  final int experience;

  @override
  int get gamesPlayed => played;

  /// "3-1-2": wins, losses, draws.
  String get record => '$wins-$losses-$draws';

  /// This standing after a rated result that moved it by [delta].
  Standing after({
    required int delta,
    required Outcome outcome,
    int experienceGained = 0,
  }) => Standing(
    rating: rating + delta,
    peakRating: math.max(peakRating, rating + delta),
    played: played + 1,
    wins: wins + (outcome == Outcome.win ? 1 : 0),
    losses: losses + (outcome == Outcome.loss ? 1 : 0),
    draws: draws + (outcome == Outcome.draw ? 1 : 0),
    experience: experience + experienceGained,
  );
}

class Player {
  const Player({
    required this.id,
    required this.displayName,
    this.standings = const {},
    this.avatarUrl,
  });

  /// A profile selected with its `ratings(*)`.
  factory Player.fromRow(Map<String, dynamic> row) => Player(
    id: row['id'] as String,
    displayName: row['display_name'] as String,
    standings: {
      for (final r
          in (row['ratings'] as List? ?? const []).cast<Map<String, dynamic>>())
        _modeOf(r): Standing.fromRow(r),
    },
  );

  final String id;
  final String displayName;

  /// The member's profile photo, or null when they haven't set one.
  final String? avatarUrl;

  /// The modes the member has a rating in. Use [standingIn].
  final Map<GameMode, Standing> standings;

  /// The member's rating and record in [mode]; the starting standing until
  /// their first result there.
  Standing standingIn(GameMode mode) =>
      standings[mode] ?? Standing.start(mode.type);

  /// The mode of [type] the member has played most, the default mode when
  /// none (ties go to the mode listed first).
  GameMode mostPlayedIn(MatchType type) => type.modes.reduce(
    (best, m) => standingIn(m).played > standingIn(best).played ? m : best,
  );

  Player copyWith({String? displayName, Map<GameMode, Standing>? standings}) =>
      Player(
        id: id,
        displayName: displayName ?? this.displayName,
        standings: standings ?? this.standings,
        avatarUrl: avatarUrl,
      );

  /// The same member with [avatarUrl] as their photo; null removes it.
  Player withAvatar(String? avatarUrl) => Player(
    id: id,
    displayName: displayName,
    standings: standings,
    avatarUrl: avatarUrl,
  );
}

/// The mode of a row with `match_type` and `mode` columns.
GameMode _modeOf(Map<String, dynamic> row) => GameMode.of(
  MatchType.values.byName(row['match_type'] as String),
  row['mode'] as String,
);

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

  /// Two settings are the same clock when preset and custom times match, so
  /// a member's recent time controls can be deduplicated.
  @override
  bool operator ==(Object other) =>
      other is ClockSetting &&
      other.preset == preset &&
      other.customBaseMinutes == customBaseMinutes &&
      other.customExtraSeconds == customExtraSeconds;

  @override
  int get hashCode =>
      Object.hash(preset, customBaseMinutes, customExtraSeconds);

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

/// A player's place in a reported result: their side and its score.
/// Teammates share a side and a score.
typedef SeatReport = ({String playerId, int side, num score});

/// One player of a result: who, on which side, and what that side scored
/// (chess 1, 0 or ½; backgammon points; SWU games won; Twin Suns players
/// outlasted).
class Seat {
  const Seat({
    required this.playerId,
    required this.name,
    required this.side,
    required this.score,
  });

  final String playerId;
  final String name;
  final int side;
  final num score;
}

/// A player of a confirmed result, with their rating before it and the
/// change it made (zero when unrated).
class RatedSeat extends Seat {
  const RatedSeat({
    required super.playerId,
    required super.name,
    required super.side,
    required super.score,
    required this.ratingBefore,
    required this.ratingDelta,
  });

  /// A `match_players` row.
  factory RatedSeat.fromRow(Map<String, dynamic> row) => RatedSeat(
    playerId: row['player_id'] as String,
    name: row['player_name'] as String,
    side: row['side'] as int,
    score: row['score'] as num,
    ratingBefore: row['rating_before'] as int,
    ratingDelta: row['rating_delta'] as int,
  );

  final int ratingBefore;
  final int ratingDelta;

  int get ratingAfter => ratingBefore + ratingDelta;

  RatedSeat named(String name) => RatedSeat(
    playerId: playerId,
    name: name,
    side: side,
    score: score,
    ratingBefore: ratingBefore,
    ratingDelta: ratingDelta,
  );
}

/// A player of a reported result, and whether they've confirmed it. The
/// reporter has from the start.
class RequestSeat extends Seat {
  const RequestSeat({
    required super.playerId,
    required super.name,
    required super.side,
    required super.score,
    required this.confirmed,
  });

  /// A `match_request_players` row with its `profiles(display_name)`.
  factory RequestSeat.fromRow(Map<String, dynamic> row) => RequestSeat(
    playerId: row['player_id'] as String,
    name: (row['profiles'] as Map?)?['display_name'] as String? ?? '',
    side: row['side'] as int,
    score: row['score'] as num,
    confirmed: row['confirmed'] as bool,
  );

  final bool confirmed;

  RequestSeat confirm() => RequestSeat(
    playerId: playerId,
    name: name,
    side: side,
    score: score,
    confirmed: true,
  );
}

/// Seats in side order, and by name within a side, as every list shows them.
List<S> _bySide<S extends Seat>(Iterable<S> seats) => seats.toList()
  ..sort(
    (a, b) => a.side != b.side
        ? a.side.compareTo(b.side)
        : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );

/// A nullable timestamp column as local time.
DateTime? parseTime(String? value) =>
    value == null ? null : DateTime.parse(value).toLocal();

/// Who played on which side and how it ended: shared by confirmed results and
/// results waiting for confirmation, in every mode.
abstract class GameReport<S extends Seat> {
  GameReport({
    required this.mode,
    required List<S> seats,
    this.rated = true,
    this.clock,
  }) : seats = _bySide(seats);

  final GameMode mode;

  /// In side order.
  final List<S> seats;

  /// False for a result that's kept in history but moves no rating.
  final bool rated;

  /// Chess only; null for games recorded before time controls were tracked.
  final ClockSetting? clock;

  S? seatOf(String playerId) =>
      seats.where((s) => s.playerId == playerId).firstOrNull;

  bool involves(String playerId) => seatOf(playerId) != null;

  /// Everyone on another side than [playerId].
  List<S> opponentsOf(String playerId) {
    final side = seatOf(playerId)!.side;
    return [
      for (final s in seats)
        if (s.side != side) s,
    ];
  }

  /// Everyone else on [playerId]'s side.
  List<S> teammatesOf(String playerId) {
    final side = seatOf(playerId)!.side;
    return [
      for (final s in seats)
        if (s.side == side && s.playerId != playerId) s,
    ];
  }

  /// The seats of each side, side 1 first.
  List<List<S>> get sides => [
    for (final side in {for (final s in seats) s.side})
      [
        for (final s in seats)
          if (s.side == side) s,
      ],
  ];

  /// Won, drew or lost against the best player on another side, as the
  /// database counts it: in a free-for-all only the winner wins.
  Outcome outcomeFor(String playerId) => Outcome.of(
    seatOf(playerId)!.score,
    opponentsOf(playerId).map((s) => s.score).reduce(math.max),
  );

  /// Finishing place: 1 for the winner; tied players share a place.
  int placeOf(String playerId) {
    final score = seatOf(playerId)!.score;
    return 1 +
        {
          for (final s in seats)
            if (s.score > score) s.side,
        }.length;
  }

  /// The winning side's score: a backgammon match's length.
  int get matchLength => seats.map((s) => s.score).reduce(math.max).toInt();

  /// "2-1" from [playerId]'s side, or the winning side's when null. Results
  /// with two sides only.
  String scoreFor([String? playerId]) {
    final mine = playerId == null
        ? seats.reduce((a, b) => b.score > a.score ? b : a)
        : seatOf(playerId)!;
    final theirs = seats.firstWhere((s) => s.side != mine.side);
    return '${_points(mine.score)}-${_points(theirs.score)}';
  }

  /// A chess duel's colours: side 1 had white.
  PieceColor colorOf(String playerId) =>
      seatOf(playerId)!.side == 1 ? PieceColor.white : PieceColor.black;
}

/// A score without a needless ".0"; chess draws read ½.
String _points(num score) => score == 0.5
    ? '½'
    : score == score.truncate()
    ? '${score.toInt()}'
    : '$score';

/// A confirmed result, rated unless [rated] is false.
class GameResult extends GameReport<RatedSeat> {
  GameResult({
    required this.id,
    required super.mode,
    required super.seats,
    super.rated,
    super.clock,
    required this.recordedBy,
    required this.playedAt,
  });

  /// A `matches` row with its `match_players(*)`.
  factory GameResult.fromRow(Map<String, dynamic> row) => GameResult(
    id: row['id'] as int,
    mode: _modeOf(row),
    seats: [
      for (final s
          in (row['match_players'] as List).cast<Map<String, dynamic>>())
        RatedSeat.fromRow(s),
    ],
    rated: row['rated'] as bool,
    clock: ClockSetting.fromRow(row),
    recordedBy: row['recorded_by'] as String,
    playedAt: DateTime.parse(row['played_at'] as String).toLocal(),
  );

  final int id;
  final String recordedBy;
  final DateTime playedAt;

  int deltaFor(String playerId) => seatOf(playerId)!.ratingDelta;
  int ratingBeforeFor(String playerId) => seatOf(playerId)!.ratingBefore;
  int ratingAfterFor(String playerId) => seatOf(playerId)!.ratingAfter;

  /// This result with each name as [nameOf] gives it (null keeps the copy).
  GameResult renamed(String? Function(String playerId) nameOf) => GameResult(
    id: id,
    mode: mode,
    seats: [for (final s in seats) s.named(nameOf(s.playerId) ?? s.name)],
    rated: rated,
    clock: clock,
    recordedBy: recordedBy,
    playedAt: playedAt,
  );
}

/// Where a reported result stands. Declined ones stay until the reporter
/// dismisses them, so the reporter learns the answer instead of watching the
/// request vanish.
enum RequestStatus { pending, declined }

/// A reported result that only counts once every other player confirms it.
class ResultRequest extends GameReport<RequestSeat> {
  ResultRequest({
    required this.id,
    required super.mode,
    required super.seats,
    super.rated,
    super.clock,
    required this.requestedBy,
    required this.createdAt,
    this.status = RequestStatus.pending,
    this.declinedBy,
    this.respondedAt,
  });

  /// A `match_requests` row with its `match_request_players(*, profiles(...))`.
  factory ResultRequest.fromRow(Map<String, dynamic> row) => ResultRequest(
    id: row['id'] as int,
    mode: _modeOf(row),
    seats: [
      for (final s
          in (row['match_request_players'] as List)
              .cast<Map<String, dynamic>>())
        RequestSeat.fromRow(s),
    ],
    rated: row['rated'] as bool,
    clock: ClockSetting.fromRow(row),
    requestedBy: row['requested_by'] as String,
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    status: RequestStatus.values.byName(row['status'] as String),
    declinedBy: row['declined_by'] as String?,
    respondedAt: parseTime(row['responded_at'] as String?),
  );

  final int id;
  final String requestedBy;
  final DateTime createdAt;
  final RequestStatus status;

  /// Who declined it; null while pending (and for results declined before
  /// more than two players could play).
  final String? declinedBy;

  /// When it was declined; null while pending.
  final DateTime? respondedAt;

  String get reporterName => seatOf(requestedBy)?.name ?? '';

  /// The players who still have to confirm.
  List<RequestSeat> get waitingOn => [
    for (final s in seats)
      if (!s.confirmed) s,
  ];

  /// Whether [playerId] is one who has to confirm or decline it now.
  bool awaits(String playerId) =>
      status == RequestStatus.pending && seatOf(playerId)?.confirmed == false;

  /// Whether [playerId] reported this and someone said no.
  bool declinedFor(String playerId) =>
      status == RequestStatus.declined && playerId == requestedBy;

  ResultRequest _with({
    List<RequestSeat>? seats,
    RequestStatus? status,
    String? declinedBy,
    DateTime? respondedAt,
  }) => ResultRequest(
    id: id,
    mode: mode,
    seats: seats ?? this.seats,
    rated: rated,
    clock: clock,
    requestedBy: requestedBy,
    createdAt: createdAt,
    status: status ?? this.status,
    declinedBy: declinedBy ?? this.declinedBy,
    respondedAt: respondedAt ?? this.respondedAt,
  );

  /// This request after [playerId] confirmed it.
  ResultRequest confirmedBy(String playerId) => _with(
    seats: [for (final s in seats) s.playerId == playerId ? s.confirm() : s],
  );

  /// This request after [playerId] declined it at [at].
  ResultRequest declined(String playerId, DateTime at) => _with(
    status: RequestStatus.declined,
    declinedBy: playerId,
    respondedAt: at,
  );
}

/// What a member reports: the mode, every player's seat (theirs included),
/// whether it's rated, and for chess the clock.
class ResultReport {
  const ResultReport({
    required this.mode,
    required this.seats,
    this.rated = true,
    this.clock,
  });

  final GameMode mode;
  final List<SeatReport> seats;
  final bool rated;
  final ClockSetting? clock;
}

/// Whether a result between two sides scoring [a] and [b] can end a game of
/// [type]. Mirrors `public.is_valid_score`.
bool isValidScore(MatchType type, num a, num b) => switch (type) {
  MatchType.chess => {(1, 0), (0, 1), (0.5, 0.5)}.contains((a, b)),
  MatchType.backgammon =>
    a == a.truncate() &&
        b == b.truncate() &&
        math.max(a, b) <= 25 &&
        isFinalScore(math.max(a, b).toInt(), a.toInt(), b.toInt()),
  MatchType.swu =>
    a == a.truncate() && b == b.truncate() && isSwuScore(a.toInt(), b.toInt()),
};

/// Why [seats] can't end a game of [mode], or null when they can. Mirrors
/// `public.invalid_result_reason`.
String? invalidResultReason(GameMode mode, List<SeatReport> seats) {
  if ({for (final s in seats) s.playerId}.length != seats.length) {
    return 'Each player can only play once';
  }
  final scores = <int, Set<num>>{};
  for (final s in seats) {
    (scores[s.side] ??= {}).add(s.score);
  }
  if (scores.values.any((s) => s.length > 1)) {
    return 'Teammates share one result';
  }
  final sideCount = scores.length;
  if (scores.keys.any((side) => side < 1 || side > sideCount)) {
    return 'Number the sides from 1';
  }
  final sizes = [
    for (var side = 1; side <= sideCount; side++)
      seats.where((s) => s.side == side).length,
  ];
  final sideScores = [
    for (var side = 1; side <= sideCount; side++) scores[side]!.single,
  ];
  final fits = switch (mode.format) {
    ResultFormat.duel => sideCount == 2 && sizes.every((n) => n == 1),
    ResultFormat.teams => sideCount == 2 && sizes.every((n) => n == 2),
    ResultFormat.boxVsTeam =>
      sideCount == 2 && sizes[0] == 1 && sizes[1] >= 2 && sizes[1] <= 5,
    ResultFormat.freeForAll =>
      sideCount >= 2 && sideCount <= 4 && sizes.every((n) => n == 1),
  };
  if (!fits) {
    return switch (mode.format) {
      ResultFormat.duel => 'Pick one opponent',
      ResultFormat.teams => 'Each team has two players',
      ResultFormat.boxVsTeam => 'One box against a team of 2 to 5',
      ResultFormat.freeForAll => 'Two to four players',
    };
  }
  if (mode.format == ResultFormat.freeForAll) {
    final outlasted = sideScores.every(
      (mine) => mine == sideScores.where((o) => o < mine).length,
    );
    return outlasted ? null : 'Give each player their finishing place';
  }
  if (!isValidScore(mode.type, sideScores[0], sideScores[1])) {
    return switch (mode.type) {
      MatchType.chess => 'Result must be win, loss or draw',
      MatchType.backgammon =>
        'The winner\'s score must equal the match length (1 to 25)',
      MatchType.swu => 'A best of three ends 2-0, 2-1, 1-0 or 1-1',
    };
  }
  return null;
}

/// Points a player gains against one opponent with their game's rules: FIBS
/// for backgammon (the match length is the winner's score), FIDE on the
/// result for chess and SWU. Mirrors `public.rating_change`.
int ratingChange(
  MatchType type,
  Standing me,
  Standing opponent,
  num myScore,
  num opponentScore,
) => switch (type) {
  MatchType.backgammon => fibsRatingChange(
    me,
    opponent,
    won: myScore > opponentScore,
    matchLength: math.max(myScore, opponentScore).toInt(),
  ),
  _ => fideRatingChange(me, opponent, Outcome.of(myScore, opponentScore).score),
};

/// Each player's rating change if a result between [seats] (with their
/// standings in its mode) were confirmed: the average of [ratingChange]
/// against every player on another side, which for two players is exactly
/// [ratingChange]. Mirrors `public.respond_to_match`; the server is the
/// source of truth and this is only used to preview a result.
Map<String, int> ratingChanges(
  MatchType type,
  List<({String playerId, int side, num score, Standing standing})> seats,
) => {
  for (final me in seats)
    me.playerId: () {
      final changes = [
        for (final them in seats)
          if (them.side != me.side)
            ratingChange(
              type,
              me.standing,
              them.standing,
              me.score,
              them.score,
            ),
      ];
      return (changes.reduce((a, b) => a + b) / changes.length).round();
    }(),
};

/// A player's rating after each result, oldest first, from [start] when they
/// haven't played.
List<int> ratingHistory(
  String playerId,
  List<GameResult> resultsOldestFirst, {
  required int start,
}) => [
  resultsOldestFirst.isEmpty
      ? start
      : resultsOldestFirst.first.ratingBeforeFor(playerId),
  for (final r in resultsOldestFirst) r.ratingAfterFor(playerId),
];
