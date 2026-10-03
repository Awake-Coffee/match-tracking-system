import 'dart:math' as math;

import '../domain/elo.dart';
import '../domain/models.dart';
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
  int _nextRequestId = 1;
  String? _meId;
  int _revision = 0;

  @override
  Player? get me => _meId == null ? null : _players[_meId];

  @override
  int get revision => _revision;

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

  MatchRequest _addRequest({
    required String by,
    required String opponentId,
    required PieceColor myColor,
    required Outcome myOutcome,
    required ClockSetting clock,
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
    final whiteDelta = fideRatingChange(white, black, whiteScore);
    final blackDelta = fideRatingChange(black, white, 1 - whiteScore);

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

    final match = ChessMatch(
      id: _matches.length + 1,
      whiteId: whiteId,
      blackId: blackId,
      whiteName: white.displayName,
      blackName: black.displayName,
      result: result,
      clock: clock,
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
  Future<void> signUp({
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
    _meId = _addPlayer(displayName.trim(), key).id;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    _meId = null;
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
  Future<List<ChessMatch>> matches({String? playerId, int limit = 50}) async =>
      _matches.reversed
          .where((m) => playerId == null || m.involves(playerId))
          .take(limit)
          .map(_withCurrentNames)
          .toList();

  @override
  Future<MatchRequest> requestMatch({
    required String opponentId,
    required PieceColor myColor,
    required Outcome myOutcome,
    required ClockSetting clock,
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
    );
    _revision++;
    notifyListeners();
    return request;
  }

  @override
  Future<List<MatchRequest>> matchRequests() async {
    final me = _requireMe();
    return _requests.reversed.where((r) => r.involves(me.id)).toList();
  }

  @override
  Future<ChessMatch?> respondToMatchRequest(
    int requestId, {
    required bool accept,
  }) async {
    final me = _requireMe();
    final request = _requests
        .where((r) => r.id == requestId && r.involves(me.id))
        .firstOrNull;
    if (request == null) {
      throw const LadderException(
        'That game is no longer waiting for confirmation.',
      );
    }
    if (accept && !request.awaits(me.id)) {
      throw const LadderException('Your opponent has to confirm this game.');
    }
    _requests.remove(request);
    final reporter = request.requestedBy;
    final match = accept
        ? _apply(
            me: reporter,
            opponentId: request.opponentId(reporter),
            myColor: request.colorOf(reporter),
            myOutcome: request.outcomeFor(reporter),
            clock: request.clock,
          )
        : null;
    _revision++;
    notifyListeners();
    return match;
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
