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

  factory BackgammonStats.fromRow(Map<String, dynamic> row) => BackgammonStats(
    rating: row['bg_rating'] as int,
    peakRating: row['bg_peak_rating'] as int,
    matchesPlayed: row['bg_matches_played'] as int,
    wins: row['bg_wins'] as int,
    losses: row['bg_losses'] as int,
    experience: row['bg_experience'] as int,
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
  });

  final String winnerId;
  final String loserId;
  final String winnerName;
  final String loserName;
  final int matchLength;
  final int loserScore;

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

/// A rated backgammon match.
class BackgammonMatch extends BackgammonResult implements RatedGame {
  const BackgammonMatch({
    required this.id,
    required super.winnerId,
    required super.loserId,
    required super.winnerName,
    required super.loserName,
    required super.matchLength,
    required super.loserScore,
    required this.winnerRatingBefore,
    required this.loserRatingBefore,
    required this.winnerRatingDelta,
    required this.loserRatingDelta,
    required this.playedAt,
  });

  factory BackgammonMatch.fromRow(Map<String, dynamic> row) => BackgammonMatch(
    id: row['id'] as int,
    winnerId: row['winner_id'] as String,
    loserId: row['loser_id'] as String,
    winnerName: joinedName(row, 'winner'),
    loserName: joinedName(row, 'loser'),
    matchLength: row['match_length'] as int,
    loserScore: row['loser_score'] as int,
    winnerRatingBefore: row['winner_rating_before'] as int,
    loserRatingBefore: row['loser_rating_before'] as int,
    winnerRatingDelta: row['winner_rating_delta'] as int,
    loserRatingDelta: row['loser_rating_delta'] as int,
    playedAt: DateTime.parse(row['played_at'] as String).toLocal(),
  );

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
    required this.requestedBy,
    required this.createdAt,
  });

  factory BackgammonMatchRequest.fromRow(Map<String, dynamic> row) =>
      BackgammonMatchRequest(
        id: row['id'] as int,
        winnerId: row['winner_id'] as String,
        loserId: row['loser_id'] as String,
        winnerName: joinedName(row, 'winner'),
        loserName: joinedName(row, 'loser'),
        matchLength: row['match_length'] as int,
        loserScore: row['loser_score'] as int,
        requestedBy: row['requested_by'] as String,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );

  final int id;
  final String requestedBy;
  final DateTime createdAt;

  /// Whether [playerId] is the one who has to confirm or decline.
  bool awaits(String playerId) => involves(playerId) && playerId != requestedBy;
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
