import 'dart:math' as math;

import 'elo.dart';
import 'models.dart';

/// Rating every member starts with on the Star Wars: Unlimited ladder.
const swuStartingRating = 1000;

/// A member's Star Wars: Unlimited standing, rated with the chess FIDE rules
/// on best-of-three match results.
class SwuStats implements FideRated {
  const SwuStats({
    this.rating = swuStartingRating,
    this.peakRating = swuStartingRating,
    this.matchesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
  });

  factory SwuStats.fromRow(Map<String, dynamic> row) => SwuStats(
    rating: row['swu_rating'] as int,
    peakRating: row['swu_peak_rating'] as int,
    matchesPlayed: row['swu_matches_played'] as int,
    wins: row['swu_wins'] as int,
    losses: row['swu_losses'] as int,
    draws: row['swu_draws'] as int,
  );

  @override
  final int rating;
  @override
  final int peakRating;
  final int matchesPlayed;
  final int wins;
  final int losses;
  final int draws;

  /// Each match counts as one FIDE game.
  @override
  int get gamesPlayed => matchesPlayed;

  SwuStats afterMatch({required int delta, required Outcome outcome}) =>
      SwuStats(
        rating: rating + delta,
        peakRating: math.max(peakRating, rating + delta),
        matchesPlayed: matchesPlayed + 1,
        wins: wins + (outcome == Outcome.win ? 1 : 0),
        losses: losses + (outcome == Outcome.loss ? 1 : 0),
        draws: draws + (outcome == Outcome.draw ? 1 : 0),
      );
}

/// Whether a best of three can end with these games won: 2-0, 2-1, 1-0 when
/// time runs out, or 1-1. Mirrors `public.is_swu_score`.
bool isSwuScore(int gamesA, int gamesB) =>
    gamesA >= 0 &&
    gamesA <= 2 &&
    gamesB >= 0 &&
    gamesB <= 2 &&
    gamesA + gamesB >= 1 &&
    gamesA + gamesB <= 3;

/// The match result for the side that won [myGames].
Outcome swuOutcome(int myGames, int opponentGames) =>
    switch (myGames.compareTo(opponentGames)) {
      > 0 => Outcome.win,
      < 0 => Outcome.loss,
      _ => Outcome.draw,
    };

/// Who played and the games each won: shared by rated matches and matches
/// still waiting for the respondent to confirm.
abstract class SwuResult {
  const SwuResult({
    required this.reporterId,
    required this.respondentId,
    required this.reporterName,
    required this.respondentName,
    required this.reporterGames,
    required this.respondentGames,
    this.rated = true,
  });

  /// Who recorded the match.
  final String reporterId;

  /// Who confirms the match.
  final String respondentId;
  final String reporterName;
  final String respondentName;
  final int reporterGames;
  final int respondentGames;

  /// False for a match that's kept in history but moves no rating.
  final bool rated;

  bool involves(String playerId) =>
      playerId == reporterId || playerId == respondentId;

  String opponentId(String playerId) =>
      playerId == reporterId ? respondentId : reporterId;

  String nameOf(String playerId) =>
      playerId == reporterId ? reporterName : respondentName;

  String opponentName(String playerId) => nameOf(opponentId(playerId));

  int gamesOf(String playerId) =>
      playerId == reporterId ? reporterGames : respondentGames;

  Outcome outcomeFor(String playerId) =>
      swuOutcome(gamesOf(playerId), gamesOf(opponentId(playerId)));

  /// Null for a draw.
  String? get winnerId => switch (outcomeFor(reporterId)) {
    Outcome.win => reporterId,
    Outcome.loss => respondentId,
    Outcome.draw => null,
  };

  /// "2-1" from [playerId]'s side, or the winner's when null.
  String scoreFor([String? playerId]) {
    final side = playerId ?? winnerId ?? reporterId;
    return '${gamesOf(side)}-${gamesOf(opponentId(side))}';
  }
}

/// A confirmed Star Wars: Unlimited match, rated unless [rated] is false.
class SwuMatch extends SwuResult implements RatedGame {
  const SwuMatch({
    required this.id,
    required super.reporterId,
    required super.respondentId,
    required super.reporterName,
    required super.respondentName,
    required super.reporterGames,
    required super.respondentGames,
    super.rated,
    required this.reporterRatingBefore,
    required this.respondentRatingBefore,
    required this.reporterRatingDelta,
    required this.respondentRatingDelta,
    required this.playedAt,
  });

  factory SwuMatch.fromRow(Map<String, dynamic> row) => SwuMatch(
    id: row['id'] as int,
    reporterId: row['reporter_id'] as String,
    respondentId: row['respondent_id'] as String,
    reporterName: joinedName(row, 'reporter'),
    respondentName: joinedName(row, 'respondent'),
    reporterGames: row['reporter_games'] as int,
    respondentGames: row['respondent_games'] as int,
    rated: row['rated'] as bool,
    reporterRatingBefore: row['reporter_rating_before'] as int,
    respondentRatingBefore: row['respondent_rating_before'] as int,
    reporterRatingDelta: row['reporter_rating_delta'] as int,
    respondentRatingDelta: row['respondent_rating_delta'] as int,
    playedAt: DateTime.parse(row['played_at'] as String).toLocal(),
  );

  final int id;
  final int reporterRatingBefore;
  final int respondentRatingBefore;
  final int reporterRatingDelta;
  final int respondentRatingDelta;
  final DateTime playedAt;

  int deltaFor(String playerId) =>
      playerId == reporterId ? reporterRatingDelta : respondentRatingDelta;

  @override
  int ratingBeforeFor(String playerId) =>
      playerId == reporterId ? reporterRatingBefore : respondentRatingBefore;

  @override
  int ratingAfterFor(String playerId) =>
      ratingBeforeFor(playerId) + deltaFor(playerId);
}

/// A reported match that only counts once the respondent confirms it.
class SwuMatchRequest extends SwuResult {
  const SwuMatchRequest({
    required this.id,
    required super.reporterId,
    required super.respondentId,
    required super.reporterName,
    required super.respondentName,
    required super.reporterGames,
    required super.respondentGames,
    super.rated,
    required this.createdAt,
    this.status = RequestStatus.pending,
    this.respondedAt,
  });

  factory SwuMatchRequest.fromRow(Map<String, dynamic> row) => SwuMatchRequest(
    id: row['id'] as int,
    reporterId: row['reporter_id'] as String,
    respondentId: row['respondent_id'] as String,
    reporterName: joinedName(row, 'reporter'),
    respondentName: joinedName(row, 'respondent'),
    reporterGames: row['reporter_games'] as int,
    respondentGames: row['respondent_games'] as int,
    rated: row['rated'] as bool,
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    status: RequestStatus.values.byName(row['status'] as String),
    respondedAt: parseTime(row['responded_at'] as String?),
  );

  final int id;
  final DateTime createdAt;
  final RequestStatus status;

  /// When the respondent declined; null while pending.
  final DateTime? respondedAt;

  /// Whether [playerId] is the one who has to confirm or decline it now.
  bool awaits(String playerId) =>
      status == RequestStatus.pending && playerId == respondentId;

  /// Whether [playerId] reported this and the respondent said no.
  bool declinedFor(String playerId) =>
      status == RequestStatus.declined && playerId == reporterId;

  /// This request after the respondent declined it at [at].
  SwuMatchRequest declined(DateTime at) => SwuMatchRequest(
    id: id,
    reporterId: reporterId,
    respondentId: respondentId,
    reporterName: reporterName,
    respondentName: respondentName,
    reporterGames: reporterGames,
    respondentGames: respondentGames,
    rated: rated,
    createdAt: createdAt,
    status: RequestStatus.declined,
    respondedAt: at,
  );
}

/// The rating change a match would cause, before it's saved.
class SwuPreview {
  SwuPreview({required this.me, required this.opponent, required this.outcome})
    : myDelta = fideRatingChange(me.swu, opponent.swu, outcome.score),
      opponentDelta = fideRatingChange(opponent.swu, me.swu, 1 - outcome.score);

  final Player me;
  final Player opponent;
  final Outcome outcome;
  final int myDelta;
  final int opponentDelta;
}
