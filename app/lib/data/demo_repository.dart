import 'dart:math' as math;

import '../domain/backgammon.dart';
import '../domain/elo.dart';
import '../domain/models.dart';
import '../domain/swu.dart';
import 'ladder_repository.dart';

/// In-memory ladder used when no Supabase project is configured.
///
/// Applies the same Elo rules as the database so the app can be tried out
/// without a backend. Starts empty and lives only in this tab.
class DemoLadderRepository extends LadderRepository {
  final Map<String, Player> _players = {};
  final Map<String, String> _emails = {};
  final List<ChessMatch> _matches = [];
  final List<MatchRequest> _requests = [];
  final List<BackgammonMatch> _backgammonMatches = [];
  final List<BackgammonMatchRequest> _backgammonRequests = [];
  final List<SwuMatch> _swuMatches = [];
  final List<SwuMatchRequest> _swuRequests = [];
  int _nextRequestId = 1;
  String? _meId;
  int _revision = 0;
  bool _recovering = false;
  String? _authLinkError;

  @override
  Player? get me => _meId == null ? null : _players[_meId];

  @override
  String? get email => _emails.entries
      .where((e) => e.value == _meId)
      .map((e) => e.key)
      .firstOrNull;

  @override
  bool get passwordRecoveryPending => _recovering;

  @override
  String? get authLinkError => _authLinkError;

  @override
  void clearAuthLinkError() {
    if (_authLinkError == null) return;
    _authLinkError = null;
    notifyListeners();
  }

  @override
  int get revision => _revision;

  @override
  void reload() {
    _revision++;
    notifyListeners();
  }

  /// When true, [signUp] creates the account but leaves the member signed
  /// out, as a project that requires email confirmation does.
  bool requireEmailConfirmation = false;

  /// Addresses [resendSignUpConfirmation] was asked to email, oldest first.
  final List<String> resentConfirmations = [];

  /// When set, [resendSignUpConfirmation] throws it, as a refused send would.
  LadderException? resendError;

  /// Addresses [sendPasswordReset] was asked to email, oldest first.
  final List<String> passwordResets = [];

  /// When set, [sendPasswordReset] throws it, as a refused send would.
  LadderException? passwordResetError;

  /// Addresses whose password [updatePassword] has changed, oldest first.
  final List<String> passwordChanges = [];

  /// Opens the app as the emailed reset link would: signs [email] in and
  /// waits for a new password.
  Future<void> openRecoveryLink(String email) async {
    await signIn(email: email, password: 'recovery-link');
    _recovering = true;
    _authLinkError = null;
    notifyListeners();
  }

  /// Opens the app as an expired, used or other-browser reset link would:
  /// nobody is signed in and the link's error is waiting to be explained.
  void openBrokenRecoveryLink() {
    _authLinkError = brokenResetLinkMessage;
    notifyListeners();
  }

  @override
  String? get modeNote =>
      'Demo mode: no Supabase project is connected. Any email and password '
      'works, and games are kept only in this browser tab.';

  Player _addPlayer(String name, String email) {
    final id = 'demo-${_players.length + 1}';
    final player = Player(
      id: id,
      displayName: _uniqueName(name),
      rating: startingRating,
      peakRating: startingRating,
      gamesPlayed: 0,
      wins: 0,
      losses: 0,
      draws: 0,
    );
    _players[id] = player;
    _emails[email.trim().toLowerCase()] = id;
    return player;
  }

  String _uniqueName(String base) {
    var candidate = base;
    var suffix = 1;
    bool taken(String n) => _players.values.any(
      (p) => p.displayName.toLowerCase() == n.toLowerCase(),
    );
    while (taken(candidate)) {
      suffix++;
      candidate = '$base $suffix';
    }
    return candidate;
  }

  ({String whiteId, String blackId}) _sides(
    String me,
    String opponentId,
    PieceColor myColor,
  ) => myColor == PieceColor.white
      ? (whiteId: me, blackId: opponentId)
      : (whiteId: opponentId, blackId: me);

  /// A pending request is read by both players, a declined one only by its
  /// reporter (as the database's policies have it).
  bool _visibleTo(String meId, RequestStatus status, String reporterId) =>
      status == RequestStatus.pending || reporterId == meId;

  MatchRequest _addRequest({
    required String by,
    required String opponentId,
    required PieceColor myColor,
    required Outcome myOutcome,
    required ClockSetting clock,
    required bool rated,
  }) {
    final (:whiteId, :blackId) = _sides(by, opponentId, myColor);
    final request = MatchRequest(
      id: _nextRequestId++,
      whiteId: whiteId,
      blackId: blackId,
      whiteName: _players[whiteId]!.displayName,
      blackName: _players[blackId]!.displayName,
      result: resultFor(myColor, myOutcome),
      clock: clock,
      rated: rated,
      requestedBy: by,
      createdAt: DateTime.now(),
    );
    _requests.add(request);
    return request;
  }

  ChessMatch _apply({
    required String me,
    required String opponentId,
    required PieceColor myColor,
    required Outcome myOutcome,
    ClockSetting? clock,
    bool rated = true,
  }) {
    final (:whiteId, :blackId) = _sides(me, opponentId, myColor);
    final white = _players[whiteId]!;
    final black = _players[blackId]!;
    final result = resultFor(myColor, myOutcome);
    final whiteScore = switch (result) {
      MatchResult.white => 1.0,
      MatchResult.black => 0.0,
      MatchResult.draw => 0.5,
    };
    final whiteDelta = rated ? fideRatingChange(white, black, whiteScore) : 0;
    final blackDelta = rated
        ? fideRatingChange(black, white, 1 - whiteScore)
        : 0;

    if (rated) {
      _players[whiteId] = white.copyWith(
        rating: white.rating + whiteDelta,
        peakRating: math.max(white.peakRating, white.rating + whiteDelta),
        gamesPlayed: white.gamesPlayed + 1,
        wins: white.wins + (result == MatchResult.white ? 1 : 0),
        losses: white.losses + (result == MatchResult.black ? 1 : 0),
        draws: white.draws + (result == MatchResult.draw ? 1 : 0),
      );
      _players[blackId] = black.copyWith(
        rating: black.rating + blackDelta,
        peakRating: math.max(black.peakRating, black.rating + blackDelta),
        gamesPlayed: black.gamesPlayed + 1,
        wins: black.wins + (result == MatchResult.black ? 1 : 0),
        losses: black.losses + (result == MatchResult.white ? 1 : 0),
        draws: black.draws + (result == MatchResult.draw ? 1 : 0),
      );
    }

    final match = ChessMatch(
      id: _matches.length + 1,
      whiteId: whiteId,
      blackId: blackId,
      whiteName: white.displayName,
      blackName: black.displayName,
      result: result,
      clock: clock,
      rated: rated,
      whiteRatingBefore: white.rating,
      blackRatingBefore: black.rating,
      whiteRatingDelta: whiteDelta,
      blackRatingDelta: blackDelta,
      playedAt: DateTime.now(),
    );
    _matches.add(match);
    return match;
  }

  ChessMatch _withCurrentNames(ChessMatch m) => ChessMatch(
    id: m.id,
    whiteId: m.whiteId,
    blackId: m.blackId,
    whiteName: _players[m.whiteId]!.displayName,
    blackName: _players[m.blackId]!.displayName,
    result: m.result,
    clock: m.clock,
    rated: m.rated,
    whiteRatingBefore: m.whiteRatingBefore,
    blackRatingBefore: m.blackRatingBefore,
    whiteRatingDelta: m.whiteRatingDelta,
    blackRatingDelta: m.blackRatingDelta,
    playedAt: m.playedAt,
  );

  Player _requireMe() {
    final me = this.me;
    if (me == null) throw const LadderException('Sign in to continue.');
    return me;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    final key = email.trim().toLowerCase();
    if (!key.contains('@')) {
      throw const LadderException('Enter an email address.');
    }
    if (password.isEmpty) throw const LadderException('Enter your password.');
    _meId = _emails[key] ?? _addPlayer(key.split('@').first, key).id;
    notifyListeners();
  }

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final key = email.trim().toLowerCase();
    if (_emails.containsKey(key)) {
      throw const LadderException(
        'That email already has an account. Sign in instead.',
      );
    }
    final player = _addPlayer(displayName.trim(), key);
    // Like a project that needs the emailed link: the account exists but the
    // member stays signed out.
    if (requireEmailConfirmation) return SignUpResult.confirmationSent;
    _meId = player.id;
    notifyListeners();
    return SignUpResult.signedIn;
  }

  @override
  Future<void> resendSignUpConfirmation(String email) async {
    final error = resendError;
    if (error != null) throw error;
    resentConfirmations.add(email.trim().toLowerCase());
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    final error = passwordResetError;
    if (error != null) throw error;
    if (!email.contains('@')) {
      throw const LadderException('Enter an email address.');
    }
    passwordResets.add(email.trim().toLowerCase());
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    _requireMe();
    final tooShort = validateNewPassword(newPassword);
    if (tooShort != null) throw LadderException(tooShort);
    passwordChanges.add(email!);
    _recovering = false;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    _meId = null;
    _recovering = false;
    notifyListeners();
  }

  @override
  Future<List<Player>> ladder() async =>
      _players.values.toList()..sort(compareLadder);

  @override
  Future<Player> player(String id) async {
    final p = _players[id];
    if (p == null) throw const LadderException('That player no longer exists.');
    return p;
  }

  @override
  Future<List<ChessMatch>> matches({
    String? playerId,
    int limit = 50,
    DateTime? before,
  }) async => _matches.reversed
      .where((m) => playerId == null || m.involves(playerId))
      .where((m) => before == null || m.playedAt.isBefore(before))
      .take(limit)
      .map(_withCurrentNames)
      .toList();

  @override
  Future<MatchRequest> requestMatch({
    required String opponentId,
    required PieceColor myColor,
    required Outcome myOutcome,
    required ClockSetting clock,
    bool rated = true,
  }) async {
    final me = _requireMe();
    if (opponentId == me.id) {
      throw const LadderException('Choose an opponent other than yourself.');
    }
    if (!_players.containsKey(opponentId)) {
      throw const LadderException('Opponent not found.');
    }
    if (!clock.isComplete) {
      throw const LadderException('Set the custom time you played.');
    }
    final request = _addRequest(
      by: me.id,
      opponentId: opponentId,
      myColor: myColor,
      myOutcome: myOutcome,
      clock: clock,
      rated: rated,
    );
    _revision++;
    notifyListeners();
    return request;
  }

  @override
  Future<List<MatchRequest>> matchRequests() async {
    final me = _requireMe();
    return _requests.reversed
        .where(
          (r) =>
              r.involves(me.id) && _visibleTo(me.id, r.status, r.requestedBy),
        )
        .toList();
  }

  @override
  Future<ChessMatch?> respondToMatchRequest(
    int requestId, {
    required bool accept,
  }) async {
    final me = _requireMe();
    final request = _requests
        .where(
          (r) =>
              r.id == requestId &&
              r.involves(me.id) &&
              r.status == RequestStatus.pending,
        )
        .firstOrNull;
    if (request == null) {
      throw const LadderException(
        'That game is no longer waiting for confirmation.',
      );
    }
    if (accept && !request.awaits(me.id)) {
      throw const LadderException('Your opponent has to confirm this game.');
    }
    final reporter = request.requestedBy;
    final index = _requests.indexOf(request);
    // Declining tells the reporter; withdrawing just removes it.
    if (!accept && reporter != me.id) {
      _requests[index] = request.declined(DateTime.now());
    } else {
      _requests.removeAt(index);
    }
    final match = accept
        ? _apply(
            me: reporter,
            opponentId: request.opponentId(reporter),
            myColor: request.colorOf(reporter),
            myOutcome: request.outcomeFor(reporter),
            clock: request.clock,
            rated: request.rated,
          )
        : null;
    _revision++;
    notifyListeners();
    return match;
  }

  @override
  Future<void> dismissMatchRequest(int requestId) async {
    final me = _requireMe();
    final removed = _requests.length;
    _requests.removeWhere((r) => r.id == requestId && r.declinedFor(me.id));
    if (_requests.length == removed) {
      throw const LadderException('That game is not waiting to be dismissed.');
    }
    _revision++;
    notifyListeners();
  }

  BackgammonMatch _backgammonWithCurrentNames(BackgammonMatch m) =>
      BackgammonMatch(
        id: m.id,
        winnerId: m.winnerId,
        loserId: m.loserId,
        winnerName: _players[m.winnerId]!.displayName,
        loserName: _players[m.loserId]!.displayName,
        matchLength: m.matchLength,
        loserScore: m.loserScore,
        rated: m.rated,
        winnerRatingBefore: m.winnerRatingBefore,
        loserRatingBefore: m.loserRatingBefore,
        winnerRatingDelta: m.winnerRatingDelta,
        loserRatingDelta: m.loserRatingDelta,
        playedAt: m.playedAt,
      );

  BackgammonMatch _applyBackgammon(BackgammonMatchRequest request) {
    final winner = _players[request.winnerId]!;
    final loser = _players[request.loserId]!;
    final length = request.matchLength;
    final rated = request.rated;
    final winnerDelta = rated
        ? fibsRatingChange(
            winner.backgammon,
            loser.backgammon,
            won: true,
            matchLength: length,
          )
        : 0;
    final loserDelta = rated
        ? fibsRatingChange(
            loser.backgammon,
            winner.backgammon,
            won: false,
            matchLength: length,
          )
        : 0;
    if (rated) {
      _players[winner.id] = winner.copyWith(
        backgammon: winner.backgammon.afterMatch(
          delta: winnerDelta,
          won: true,
          matchLength: length,
        ),
      );
      _players[loser.id] = loser.copyWith(
        backgammon: loser.backgammon.afterMatch(
          delta: loserDelta,
          won: false,
          matchLength: length,
        ),
      );
    }
    final match = BackgammonMatch(
      id: _backgammonMatches.length + 1,
      winnerId: winner.id,
      loserId: loser.id,
      winnerName: winner.displayName,
      loserName: loser.displayName,
      matchLength: length,
      loserScore: request.loserScore,
      rated: rated,
      winnerRatingBefore: winner.backgammon.rating,
      loserRatingBefore: loser.backgammon.rating,
      winnerRatingDelta: winnerDelta,
      loserRatingDelta: loserDelta,
      playedAt: DateTime.now(),
    );
    _backgammonMatches.add(match);
    return match;
  }

  @override
  Future<List<Player>> backgammonLadder() async =>
      _players.values.toList()..sort(compareBackgammonLadder);

  @override
  Future<List<BackgammonMatch>> backgammonMatches({
    String? playerId,
    int limit = 50,
    DateTime? before,
  }) async => _backgammonMatches.reversed
      .where((m) => playerId == null || m.involves(playerId))
      .where((m) => before == null || m.playedAt.isBefore(before))
      .take(limit)
      .map(_backgammonWithCurrentNames)
      .toList();

  @override
  Future<BackgammonMatchRequest> requestBackgammonMatch({
    required String opponentId,
    required int matchLength,
    required int myScore,
    required int opponentScore,
    bool rated = true,
  }) async {
    final me = _requireMe();
    if (opponentId == me.id) {
      throw const LadderException('Choose an opponent other than yourself.');
    }
    final opponent = _players[opponentId];
    if (opponent == null) throw const LadderException('Opponent not found.');
    if (matchLength < 1 ||
        matchLength > 25 ||
        !isFinalScore(matchLength, myScore, opponentScore)) {
      throw const LadderException(
        'The winner\'s score must equal the match length.',
      );
    }
    final iWon = myScore == matchLength;
    final (winner, loser) = iWon ? (me, opponent) : (opponent, me);
    final request = BackgammonMatchRequest(
      id: _nextRequestId++,
      winnerId: winner.id,
      loserId: loser.id,
      winnerName: winner.displayName,
      loserName: loser.displayName,
      matchLength: matchLength,
      loserScore: math.min(myScore, opponentScore),
      rated: rated,
      requestedBy: me.id,
      createdAt: DateTime.now(),
    );
    _backgammonRequests.add(request);
    _revision++;
    notifyListeners();
    return request;
  }

  @override
  Future<List<BackgammonMatchRequest>> backgammonMatchRequests() async {
    final me = _requireMe();
    return _backgammonRequests.reversed
        .where(
          (r) =>
              r.involves(me.id) && _visibleTo(me.id, r.status, r.requestedBy),
        )
        .toList();
  }

  @override
  Future<BackgammonMatch?> respondToBackgammonMatchRequest(
    int requestId, {
    required bool accept,
  }) async {
    final me = _requireMe();
    final request = _backgammonRequests
        .where(
          (r) =>
              r.id == requestId &&
              r.involves(me.id) &&
              r.status == RequestStatus.pending,
        )
        .firstOrNull;
    if (request == null) {
      throw const LadderException(
        'That match is no longer waiting for confirmation.',
      );
    }
    if (accept && !request.awaits(me.id)) {
      throw const LadderException('Your opponent has to confirm this match.');
    }
    final index = _backgammonRequests.indexOf(request);
    if (!accept && request.requestedBy != me.id) {
      _backgammonRequests[index] = request.declined(DateTime.now());
    } else {
      _backgammonRequests.removeAt(index);
    }
    final match = accept ? _applyBackgammon(request) : null;
    _revision++;
    notifyListeners();
    return match;
  }

  @override
  Future<void> dismissBackgammonMatchRequest(int requestId) async {
    final me = _requireMe();
    final before = _backgammonRequests.length;
    _backgammonRequests.removeWhere(
      (r) => r.id == requestId && r.declinedFor(me.id),
    );
    if (_backgammonRequests.length == before) {
      throw const LadderException('That match is not waiting to be dismissed.');
    }
    _revision++;
    notifyListeners();
  }

  SwuMatch _swuWithCurrentNames(SwuMatch m) => SwuMatch(
    id: m.id,
    reporterId: m.reporterId,
    respondentId: m.respondentId,
    reporterName: _players[m.reporterId]!.displayName,
    respondentName: _players[m.respondentId]!.displayName,
    reporterGames: m.reporterGames,
    respondentGames: m.respondentGames,
    rated: m.rated,
    reporterRatingBefore: m.reporterRatingBefore,
    respondentRatingBefore: m.respondentRatingBefore,
    reporterRatingDelta: m.reporterRatingDelta,
    respondentRatingDelta: m.respondentRatingDelta,
    playedAt: m.playedAt,
  );

  SwuMatch _applySwu(SwuMatchRequest request) {
    final reporter = _players[request.reporterId]!;
    final respondent = _players[request.respondentId]!;
    final reporterOutcome = request.outcomeFor(reporter.id);
    final respondentOutcome = request.outcomeFor(respondent.id);
    final rated = request.rated;
    final reporterDelta = rated
        ? fideRatingChange(reporter.swu, respondent.swu, reporterOutcome.score)
        : 0;
    final respondentDelta = rated
        ? fideRatingChange(
            respondent.swu,
            reporter.swu,
            respondentOutcome.score,
          )
        : 0;
    if (rated) {
      _players[reporter.id] = reporter.copyWith(
        swu: reporter.swu.afterMatch(
          delta: reporterDelta,
          outcome: reporterOutcome,
        ),
      );
      _players[respondent.id] = respondent.copyWith(
        swu: respondent.swu.afterMatch(
          delta: respondentDelta,
          outcome: respondentOutcome,
        ),
      );
    }
    final match = SwuMatch(
      id: _swuMatches.length + 1,
      reporterId: reporter.id,
      respondentId: respondent.id,
      reporterName: reporter.displayName,
      respondentName: respondent.displayName,
      reporterGames: request.reporterGames,
      respondentGames: request.respondentGames,
      rated: rated,
      reporterRatingBefore: reporter.swu.rating,
      respondentRatingBefore: respondent.swu.rating,
      reporterRatingDelta: reporterDelta,
      respondentRatingDelta: respondentDelta,
      playedAt: DateTime.now(),
    );
    _swuMatches.add(match);
    return match;
  }

  @override
  Future<List<Player>> swuLadder() async =>
      _players.values.toList()..sort(compareSwuLadder);

  @override
  Future<List<SwuMatch>> swuMatches({
    String? playerId,
    int limit = 50,
    DateTime? before,
  }) async => _swuMatches.reversed
      .where((m) => playerId == null || m.involves(playerId))
      .where((m) => before == null || m.playedAt.isBefore(before))
      .take(limit)
      .map(_swuWithCurrentNames)
      .toList();

  @override
  Future<SwuMatchRequest> requestSwuMatch({
    required String opponentId,
    required int myGames,
    required int opponentGames,
    bool rated = true,
  }) async {
    final me = _requireMe();
    if (opponentId == me.id) {
      throw const LadderException('Choose an opponent other than yourself.');
    }
    final opponent = _players[opponentId];
    if (opponent == null) throw const LadderException('Opponent not found.');
    if (!isSwuScore(myGames, opponentGames)) {
      throw const LadderException('A best of three ends 2-0, 2-1, 1-0 or 1-1.');
    }
    final request = SwuMatchRequest(
      id: _nextRequestId++,
      reporterId: me.id,
      respondentId: opponent.id,
      reporterName: me.displayName,
      respondentName: opponent.displayName,
      reporterGames: myGames,
      respondentGames: opponentGames,
      rated: rated,
      createdAt: DateTime.now(),
    );
    _swuRequests.add(request);
    _revision++;
    notifyListeners();
    return request;
  }

  @override
  Future<List<SwuMatchRequest>> swuMatchRequests() async {
    final me = _requireMe();
    return _swuRequests.reversed
        .where(
          (r) => r.involves(me.id) && _visibleTo(me.id, r.status, r.reporterId),
        )
        .toList();
  }

  @override
  Future<SwuMatch?> respondToSwuMatchRequest(
    int requestId, {
    required bool accept,
  }) async {
    final me = _requireMe();
    final request = _swuRequests
        .where(
          (r) =>
              r.id == requestId &&
              r.involves(me.id) &&
              r.status == RequestStatus.pending,
        )
        .firstOrNull;
    if (request == null) {
      throw const LadderException(
        'That match is no longer waiting for confirmation.',
      );
    }
    if (accept && !request.awaits(me.id)) {
      throw const LadderException('Your opponent has to confirm this match.');
    }
    final index = _swuRequests.indexOf(request);
    if (!accept && request.reporterId != me.id) {
      _swuRequests[index] = request.declined(DateTime.now());
    } else {
      _swuRequests.removeAt(index);
    }
    final match = accept ? _applySwu(request) : null;
    _revision++;
    notifyListeners();
    return match;
  }

  @override
  Future<void> dismissSwuMatchRequest(int requestId) async {
    final me = _requireMe();
    final before = _swuRequests.length;
    _swuRequests.removeWhere((r) => r.id == requestId && r.declinedFor(me.id));
    if (_swuRequests.length == before) {
      throw const LadderException('That match is not waiting to be dismissed.');
    }
    _revision++;
    notifyListeners();
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final me = _requireMe();
    final name = displayName.trim();
    final taken = _players.values.any(
      (p) => p.id != me.id && p.displayName.toLowerCase() == name.toLowerCase(),
    );
    if (taken) throw const LadderException('That name is taken. Try another.');
    _players[me.id] = me.copyWith(displayName: name);
    _revision++;
    notifyListeners();
  }
}
