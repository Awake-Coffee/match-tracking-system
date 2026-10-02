import 'package:flutter/foundation.dart';

import '../domain/models.dart';

/// Thrown with a message that can be shown to the member as-is.
class LadderException implements Exception {
  const LadderException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Everything the UI needs from the backend.
///
/// Notifies listeners when the signed-in member changes or when data that
/// screens show (ratings, matches) has changed, so they can reload.
abstract class LadderRepository extends ChangeNotifier {
  /// The signed-in member's profile, or null when signed out.
  Player? get me;

  bool get isSignedIn => me != null;

  /// Bumped whenever ratings or matches change.
  int get revision;

  /// Short description shown on the sign-in screen, or null for production.
  String? get modeNote => null;

  Future<void> signIn({required String email, required String password});

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  });

  Future<void> signOut();

  /// Every member, highest rating first.
  Future<List<Player>> ladder();

  Future<Player> player(String id);

  /// Newest first. When [playerId] is set, only that member's games.
  Future<List<ChessMatch>> matches({String? playerId, int limit = 50});

  /// Records a game the signed-in member played and returns it.
  Future<ChessMatch> recordMatch({
    required String opponentId,
    required PieceColor myColor,
    required Outcome myOutcome,
  });

  Future<void> updateProfile({String? displayName, String? design});
}

/// Ladder order: rating, then more games played, then name.
int compareLadder(Player a, Player b) {
  final byRating = b.rating.compareTo(a.rating);
  if (byRating != 0) return byRating;
  final byGames = b.gamesPlayed.compareTo(a.gamesPlayed);
  if (byGames != 0) return byGames;
  return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
}

String? validateDisplayName(String? value) {
  final name = value?.trim() ?? '';
  if (name.length < 2) return 'Use at least 2 characters';
  if (name.length > 32) return 'Use 32 characters or fewer';
  return null;
}
