import 'dart:math' as math;

import 'models.dart';

/// Rating every member starts with on the backgammon ladder (FIBS convention).
const backgammonStartingRating = 1500;

/// Match lengths offered when recording; the database accepts 1 to 25.
const backgammonMatchLengths = [1, 3, 5, 7, 9, 11];

/// A member's backgammon standing, kept apart from their chess rating.
class BackgammonStats {
  const BackgammonStats({
    this.rating = backgammonStartingRating,
    this.peakRating = backgammonStartingRating,
    this.matchesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.experience = 0,
  });

  /// A member's backgammon row in `ratings`.
  factory BackgammonStats.fromRow(Map<String, dynamic> row) => BackgammonStats(
    rating: row['rating'] as int,
    peakRating: row['peak_rating'] as int,
    matchesPlayed: row['played'] as int,
    wins: row['wins'] as int,
    losses: row['losses'] as int,
    experience: row['experience'] as int,
  );

  final int rating;
  final int peakRating;
  final int matchesPlayed;
  final int wins;
  final int losses;

  /// Summed lengths of every match played; FIBS moves newcomers faster.
  final int experience;

  BackgammonStats afterMatch({
    required int delta,
    required bool won,
    required int matchLength,
  }) => BackgammonStats(
    rating: rating + delta,
    peakRating: math.max(peakRating, rating + delta),
    matchesPlayed: matchesPlayed + 1,
    wins: wins + (won ? 1 : 0),
    losses: losses + (won ? 0 : 1),
    experience: experience + matchLength,
  );
}

/// Points [player] gains from a match to [matchLength] points (FIBS).
///
/// Mirrors `public.fibs_rating_change` in the Supabase migration; the server
/// is the source of truth and this is only used to preview a result.
int fibsRatingChange(
  BackgammonStats player,
  BackgammonStats opponent, {
  required bool won,
  required int matchLength,
}) {
  final root = math.sqrt(matchLength);
  final winChance =
      1 / (1 + math.pow(10, (opponent.rating - player.rating) * root / 2000));
  final experienceMultiplier = math.max(1.0, 5 - player.experience / 100);
  return (4 * root * experienceMultiplier * ((won ? 1 : 0) - winChance) + 0.5)
      .floor();
}

/// Whether [scoreA] and [scoreB] can end a match to [matchLength]: exactly
/// one player reached the length.
bool isFinalScore(int matchLength, int scoreA, int scoreB) =>
    math.max(scoreA, scoreB) == matchLength &&
    math.min(scoreA, scoreB) >= 0 &&
    math.min(scoreA, scoreB) < matchLength;

/// The winning and losing sides of a backgammon result row.
({String winner, String loser}) _sides(Map<String, dynamic> row) =>
    sideScore(row, player1) > sideScore(row, player2)
    ? (winner: player1, loser: player2)
    : (winner: player2, loser: player1);

/// Who won a match and by how much: shared by rated matches and matches
/// still waiting for the opponent to confirm.
abstract class BackgammonResult {
  const BackgammonResult({
    required this.winnerId,
    required this.loserId,
    required this.winnerName,
    required this.loserName,
    required this.matchLength,
    required this.loserScore,
    this.rated = true,
  });

  final String winnerId;
  final String loserId;
  final String winnerName;
  final String loserName;
  final int matchLength;
  final int loserScore;

  /// False for a match that's kept in history but moves no rating.
  final bool rated;

  bool involves(String playerId) => playerId == winnerId || playerId == loserId;

  bool wonBy(String playerId) => playerId == winnerId;

  String opponentId(String playerId) =>
      playerId == winnerId ? loserId : winnerId;

  String opponentName(String playerId) =>
      playerId == winnerId ? loserName : winnerName;

  /// "5-3" from the winner's side, or "3-5" from [playerId]'s when they lost.
  String scoreFor([String? playerId]) => playerId == loserId
      ? '$loserScore-$matchLength'
      : '$matchLength-$loserScore';
}

/// A confirmed backgammon match, rated unless [rated] is false.
class BackgammonMatch extends BackgammonResult implements RatedGame {
  const BackgammonMatch({
    required this.id,
    required super.winnerId,
    required super.loserId,
    required super.winnerName,
    required super.loserName,
    required super.matchLength,
    required super.loserScore,
    super.rated,
    required this.winnerRatingBefore,
    required this.loserRatingBefore,
    required this.winnerRatingDelta,
    required this.loserRatingDelta,
    required this.playedAt,
  });

  factory BackgammonMatch.fromRow(Map<String, dynamic> row) {
    final (:winner, :loser) = _sides(row);
    return BackgammonMatch(
      id: row['id'] as int,
      winnerId: row['${winner}_id'] as String,
      loserId: row['${loser}_id'] as String,
      winnerName: joinedName(row, winner),
      loserName: joinedName(row, loser),
      matchLength: sideScore(row, winner).toInt(),
      loserScore: sideScore(row, loser).toInt(),
      rated: row['rated'] as bool,
      winnerRatingBefore: row['${winner}_rating_before'] as int,
      loserRatingBefore: row['${loser}_rating_before'] as int,
      winnerRatingDelta: row['${winner}_rating_delta'] as int,
      loserRatingDelta: row['${loser}_rating_delta'] as int,
      playedAt: DateTime.parse(row['played_at'] as String).toLocal(),
    );
  }

  final int id;
  final int winnerRatingBefore;
  final int loserRatingBefore;
  final int winnerRatingDelta;
  final int loserRatingDelta;
  final DateTime playedAt;

  int deltaFor(String playerId) =>
      playerId == winnerId ? winnerRatingDelta : loserRatingDelta;

  @override
  int ratingBeforeFor(String playerId) =>
      playerId == winnerId ? winnerRatingBefore : loserRatingBefore;

  @override
  int ratingAfterFor(String playerId) =>
      ratingBeforeFor(playerId) + deltaFor(playerId);
}

/// A reported match that only counts once the other player confirms it.
class BackgammonMatchRequest extends BackgammonResult {
  const BackgammonMatchRequest({
    required this.id,
    required super.winnerId,
    required super.loserId,
    required super.winnerName,
    required super.loserName,
    required super.matchLength,
    required super.loserScore,
    super.rated,
    required this.requestedBy,
    required this.createdAt,
    this.status = RequestStatus.pending,
    this.respondedAt,
  });

  factory BackgammonMatchRequest.fromRow(Map<String, dynamic> row) {
    final (:winner, :loser) = _sides(row);
    return BackgammonMatchRequest(
      id: row['id'] as int,
      winnerId: row['${winner}_id'] as String,
      loserId: row['${loser}_id'] as String,
      winnerName: joinedName(row, winner),
      loserName: joinedName(row, loser),
      matchLength: sideScore(row, winner).toInt(),
      loserScore: sideScore(row, loser).toInt(),
      rated: row['rated'] as bool,
      requestedBy: row['requested_by'] as String,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      status: RequestStatus.values.byName(row['status'] as String),
      respondedAt: parseTime(row['responded_at'] as String?),
    );
  }

  final int id;
  final String requestedBy;
  final DateTime createdAt;
  final RequestStatus status;

  /// When the opponent declined; null while pending.
  final DateTime? respondedAt;

  /// Whether [playerId] is the one who has to confirm or decline it now.
  bool awaits(String playerId) =>
      status == RequestStatus.pending &&
      involves(playerId) &&
      playerId != requestedBy;

  /// Whether [playerId] reported this and the opponent said no.
  bool declinedFor(String playerId) =>
      status == RequestStatus.declined && playerId == requestedBy;

  /// This request after the opponent declined it at [at].
  BackgammonMatchRequest declined(DateTime at) => BackgammonMatchRequest(
    id: id,
    winnerId: winnerId,
    loserId: loserId,
    winnerName: winnerName,
    loserName: loserName,
    matchLength: matchLength,
    loserScore: loserScore,
    rated: rated,
    requestedBy: requestedBy,
    createdAt: createdAt,
    status: RequestStatus.declined,
    respondedAt: at,
  );
}

/// The rating change a match would cause, before it's saved.
class BackgammonPreview {
  BackgammonPreview({
    required this.me,
    required this.opponent,
    required this.won,
    required this.matchLength,
  }) : myDelta = fibsRatingChange(
         me.backgammon,
         opponent.backgammon,
         won: won,
         matchLength: matchLength,
       ),
       opponentDelta = fibsRatingChange(
         opponent.backgammon,
         me.backgammon,
         won: !won,
         matchLength: matchLength,
       );

  final Player me;
  final Player opponent;
  final bool won;
  final int matchLength;
  final int myDelta;
  final int opponentDelta;
}
