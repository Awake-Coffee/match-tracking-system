import 'package:flutter/foundation.dart';

import '../domain/backgammon.dart';
import '../domain/models.dart';
import '../domain/swu.dart';

/// Thrown with a message that can be shown to the member as-is.
class LadderException implements Exception {
  const LadderException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// How a sign-up ended. Both are successes: the second just isn't signed in.
enum SignUpResult {
  /// The account exists and the member is signed in.
  signedIn,

  /// The account exists but the member must open the emailed link first.
  confirmationSent,
}

/// Everything the UI needs from the backend.
///
/// Notifies listeners when the signed-in member changes or when data that
/// screens show (ratings, matches) has changed, so they can reload.
abstract class LadderRepository extends ChangeNotifier {
  /// The signed-in member's profile, or null when signed out.
  Player? get me;

  bool get isSignedIn => me != null;

  /// Bumped whenever ratings, matches or pending games change.
  int get revision;

  /// Short description shown on the sign-in screen, or null for production.
  String? get modeNote => null;

  /// Drops cached data and refetches everything on screen, as if data had
  /// changed: pull-to-refresh, retry and the Refresh button.
  void reload();

  Future<void> signIn({required String email, required String password});

  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required String displayName,
  });

  /// Sends the sign-up confirmation email to [email] again.
  Future<void> resendSignUpConfirmation(String email);

  Future<void> signOut();

  /// Every member, highest rating first.
  Future<List<Player>> ladder();

  Future<Player> player(String id);

  /// Newest first. When [playerId] is set, only that member's games.
  Future<List<ChessMatch>> matches({String? playerId, int limit = 50});

  /// Reports a game the signed-in member played. It is rated only once the
  /// opponent accepts it with [respondToMatchRequest], and never when
  /// [rated] is false.
  Future<MatchRequest> requestMatch({
    required String opponentId,
    required PieceColor myColor,
    required Outcome myOutcome,
    required ClockSetting clock,
    bool rated = true,
  });

  /// Games involving the signed-in member that wait for confirmation,
  /// newest first.
  Future<List<MatchRequest>> matchRequests();

  /// The opponent accepts ([accept]) and gets the confirmed game back, or
  /// either player drops the request and gets null.
  Future<ChessMatch?> respondToMatchRequest(
    int requestId, {
    required bool accept,
  });

  /// Every member, best backgammon rating first.
  Future<List<Player>> backgammonLadder();

  /// Newest first. When [playerId] is set, only that member's matches.
  Future<List<BackgammonMatch>> backgammonMatches({
    String? playerId,
    int limit = 50,
  });

  /// Reports a match the signed-in member played. It is rated only once the
  /// opponent accepts it with [respondToBackgammonMatchRequest], and never
  /// when [rated] is false.
  Future<BackgammonMatchRequest> requestBackgammonMatch({
    required String opponentId,
    required int matchLength,
    required int myScore,
    required int opponentScore,
    bool rated = true,
  });

  /// Matches involving the signed-in member that wait for confirmation,
  /// newest first.
  Future<List<BackgammonMatchRequest>> backgammonMatchRequests();

  /// The opponent accepts ([accept]) and gets the confirmed match back, or
  /// either player drops the request and gets null.
  Future<BackgammonMatch?> respondToBackgammonMatchRequest(
    int requestId, {
    required bool accept,
  });

  /// Every member, best Star Wars: Unlimited rating first.
  Future<List<Player>> swuLadder();

  /// Newest first. When [playerId] is set, only that member's matches.
  Future<List<SwuMatch>> swuMatches({String? playerId, int limit = 50});

  /// Reports a best of three the signed-in member played. It is rated only
  /// once the opponent accepts it with [respondToSwuMatchRequest], and never
  /// when [rated] is false.
  Future<SwuMatchRequest> requestSwuMatch({
    required String opponentId,
    required int myGames,
    required int opponentGames,
    bool rated = true,
  });

  /// Matches involving the signed-in member that wait for confirmation,
  /// newest first.
  Future<List<SwuMatchRequest>> swuMatchRequests();

  /// The opponent accepts ([accept]) and gets the confirmed match back, or
  /// either player drops the request and gets null.
  Future<SwuMatch?> respondToSwuMatchRequest(
    int requestId, {
    required bool accept,
  });

  Future<void> updateDisplayName(String displayName);
}

/// Ladder order in one game: rating, then more results played, then name.
Comparator<Player> _ladderOrder(
  ({int rating, int played}) Function(Player) standingIn,
) => (a, b) {
  final (rating: ratingA, played: playedA) = standingIn(a);
  final (rating: ratingB, played: playedB) = standingIn(b);
  final byRating = ratingB.compareTo(ratingA);
  if (byRating != 0) return byRating;
  final byPlayed = playedB.compareTo(playedA);
  if (byPlayed != 0) return byPlayed;
  return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
};

final compareLadder = _ladderOrder(
  (p) => (rating: p.rating, played: p.gamesPlayed),
);

final compareBackgammonLadder = _ladderOrder(
  (p) => (rating: p.backgammon.rating, played: p.backgammon.matchesPlayed),
);

final compareSwuLadder = _ladderOrder(
  (p) => (rating: p.swu.rating, played: p.swu.matchesPlayed),
);

String? validateDisplayName(String? value) {
  final name = value?.trim() ?? '';
  if (name.length < 2) return 'Use at least 2 characters';
  if (name.length > 32) return 'Use 32 characters or fewer';
  return null;
}
