import 'elo.dart';

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

class Player {
  const Player({
    required this.id,
    required this.displayName,
    required this.rating,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.design,
  });

  factory Player.fromRow(Map<String, dynamic> row) => Player(
        id: row['id'] as String,
        displayName: row['display_name'] as String,
        rating: row['rating'] as int,
        gamesPlayed: row['games_played'] as int,
        wins: row['wins'] as int,
        losses: row['losses'] as int,
        draws: row['draws'] as int,
        design: row['design'] as String,
      );

  final String id;
  final String displayName;
  final int rating;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final String design;

  Player copyWith({
    String? displayName,
    int? rating,
    int? gamesPlayed,
    int? wins,
    int? losses,
    int? draws,
    String? design,
  }) =>
      Player(
        id: id,
        displayName: displayName ?? this.displayName,
        rating: rating ?? this.rating,
        gamesPlayed: gamesPlayed ?? this.gamesPlayed,
        wins: wins ?? this.wins,
        losses: losses ?? this.losses,
        draws: draws ?? this.draws,
        design: design ?? this.design,
      );
}

class ChessMatch {
  const ChessMatch({
    required this.id,
    required this.whiteId,
    required this.blackId,
    required this.whiteName,
    required this.blackName,
    required this.result,
    required this.whiteRatingBefore,
    required this.blackRatingBefore,
    required this.ratingDelta,
    required this.playedAt,
  });

  factory ChessMatch.fromRow(Map<String, dynamic> row) => ChessMatch(
        id: row['id'] as int,
        whiteId: row['white_id'] as String,
        blackId: row['black_id'] as String,
        whiteName: (row['white'] as Map?)?['display_name'] as String? ?? '',
        blackName: (row['black'] as Map?)?['display_name'] as String? ?? '',
        result: MatchResult.values.byName(row['result'] as String),
        whiteRatingBefore: row['white_rating_before'] as int,
        blackRatingBefore: row['black_rating_before'] as int,
        ratingDelta: row['rating_delta'] as int,
        playedAt: DateTime.parse(row['played_at'] as String).toLocal(),
      );

  final int id;
  final String whiteId;
  final String blackId;
  final String whiteName;
  final String blackName;
  final MatchResult result;
  final int whiteRatingBefore;
  final int blackRatingBefore;

  /// Points white gained; black gained the negative.
  final int ratingDelta;
  final DateTime playedAt;

  bool involves(String playerId) => playerId == whiteId || playerId == blackId;

  PieceColor colorOf(String playerId) =>
      playerId == whiteId ? PieceColor.white : PieceColor.black;

  int deltaFor(String playerId) =>
      playerId == whiteId ? ratingDelta : -ratingDelta;

  int ratingBeforeFor(String playerId) =>
      playerId == whiteId ? whiteRatingBefore : blackRatingBefore;

  int ratingAfterFor(String playerId) =>
      ratingBeforeFor(playerId) + deltaFor(playerId);

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

/// The rating change a game would cause, before it's saved.
class MatchPreview {
  MatchPreview({
    required this.me,
    required this.opponent,
    required this.outcome,
  }) : myDelta = eloDelta(me.rating, opponent.rating, outcome.score);

  final Player me;
  final Player opponent;
  final Outcome outcome;
  final int myDelta;

  int get opponentDelta => -myDelta;
  int get myRatingAfter => me.rating + myDelta;
  int get opponentRatingAfter => opponent.rating + opponentDelta;
}

/// A player's rating after each game, oldest first, starting at 1000.
List<int> ratingHistory(String playerId, List<ChessMatch> matchesOldestFirst) {
  final points = <int>[
    matchesOldestFirst.isEmpty
        ? startingRating
        : matchesOldestFirst.first.ratingBeforeFor(playerId),
  ];
  for (final m in matchesOldestFirst) {
    points.add(m.ratingAfterFor(playerId));
  }
  return points;
}
