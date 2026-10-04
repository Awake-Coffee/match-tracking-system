import 'package:flutter/foundation.dart';

import '../domain/models.dart';

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

  /// The signed-in member's sign-in email, or null when signed out. Profiles
  /// don't carry it; it belongs to the auth account.
  String? get email;

  /// True from the moment the app is opened from a password-recovery link
  /// until the member saves a new password or signs out. The member is
  /// signed in by the link, but only to choose a new password.
  bool get passwordRecoveryPending;

  /// Why the password-reset link the app was just opened from didn't work
  /// (expired, already used, or opened in another browser), or null. Without
  /// it the member lands on a plain sign-in form with no idea why.
  String? get authLinkError;

  /// Forgets [authLinkError] once the member has moved on from it.
  void clearAuthLinkError();

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

  /// Emails a link to [email] for choosing a new password. Says nothing about
  /// whether an account exists, so it can't be used to probe for members.
  Future<void> sendPasswordReset(String email);

  /// Sets the signed-in member's password: from Settings, or after opening a
  /// recovery link. Ends [passwordRecoveryPending].
  Future<void> updatePassword(String newPassword);

  Future<void> signOut();

  /// Deletes the signed-in member's account and signs them out: their login,
  /// profile, ratings and open requests go; confirmed results stay in the
  /// history under the name they had when the account was deleted.
  Future<void> deleteAccount();

  /// Every member, with their standing in every mode they've played.
  Future<List<Player>> members();

  Future<Player> player(String id);

  /// Confirmed results of [type], newest first. When [mode] is set, only that
  /// mode's; when [playerId] is set, only that member's. When [before] is
  /// set, only results played before it: pass the `playedAt` of the oldest
  /// result already loaded to fetch the next page.
  Future<List<GameResult>> results(
    MatchType type, {
    GameMode? mode,
    String? playerId,
    int limit = 50,
    DateTime? before,
  });

  /// Reports a result the signed-in member played. It is rated only once
  /// every other player accepts it with [respondToRequest], and never when
  /// the report isn't rated.
  Future<ResultRequest> reportResult(ResultReport report);

  /// Results in every game involving the signed-in member that wait for
  /// confirmation, newest first, plus the ones they reported that someone
  /// declined, until they [dismissRequest].
  Future<List<ResultRequest>> requests();

  /// A player confirms ([accept]) and gets the rated result back once every
  /// player has (null while others still have to), or drops the request
  /// (declines it, or withdraws their own report) and gets null.
  Future<GameResult?> respondToRequest(int requestId, {required bool accept});

  /// The reporter clears a result someone declined.
  Future<void> dismissRequest(int requestId);

  Future<void> updateDisplayName(String displayName);
}

/// [players] in ladder order for [mode]: rating, then more results played,
/// then name.
List<Player> ladderOf(List<Player> players, GameMode mode) =>
    players.toList()..sort((a, b) {
      final standingA = a.standingIn(mode);
      final standingB = b.standingIn(mode);
      final byRating = standingB.rating.compareTo(standingA.rating);
      if (byRating != 0) return byRating;
      final byPlayed = standingB.played.compareTo(standingA.played);
      if (byPlayed != 0) return byPlayed;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

String? validateDisplayName(String? value) {
  final name = value?.trim() ?? '';
  if (name.length < 2) return 'Use at least 2 characters';
  if (name.length > 32) return 'Use 32 characters or fewer';
  return null;
}

/// Shown when a reset link fails. Both causes look the same from here, and
/// the cure for both is a fresh link opened where it was asked for.
const brokenResetLinkMessage =
    'That link has expired or was opened in a different browser. '
    'Ask for a new one.';

/// Same rule for choosing a password at sign-up, in Settings and on reset.
String? validateNewPassword(String? value) =>
    (value == null || value.length < 8) ? 'Use at least 8 characters' : null;
