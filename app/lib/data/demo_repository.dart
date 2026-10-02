import 'dart:math' as math;

import '../domain/elo.dart';
import '../domain/models.dart';
import 'ladder_repository.dart';

/// In-memory ladder used when no Supabase project is configured.
///
/// Applies the same Elo rules as the database so the app (and every design)
/// can be tried out without a backend. Data lives only in this tab.
class DemoLadderRepository extends LadderRepository {
  DemoLadderRepository({bool seed = true, DateTime? now})
      : _now = now ?? DateTime.now() {
    if (seed) _seed();
  }

  final DateTime _now;
  final Map<String, Player> _players = {};
  final Map<String, String> _emails = {};
  final List<ChessMatch> _matches = [];
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

  void _seed() {
    const names = [
      'Ana', 'Bogdan', 'Chloe', 'Dev', 'Elena', 'Femi', 'Grace', 'Hiro', //
    ];
    for (final name in names) {
      _addPlayer(name, '${name.toLowerCase()}@awake.coffee');
    }
    final rng = math.Random(7);
    final ids = _players.keys.toList();
    // Stronger players (earlier in the list) win more often.
    for (var i = 0; i < 46; i++) {
      final a = rng.nextInt(ids.length);
      var b = rng.nextInt(ids.length - 1);
      if (b >= a) b++;
      final roll = rng.nextDouble() + (b - a) * 0.06;
      final outcome = roll > 0.62
          ? Outcome.win
          : roll > 0.48
              ? Outcome.draw
              : Outcome.loss;
      _apply(
        me: ids[a],
        opponentId: ids[b],
        myColor: rng.nextBool() ? PieceColor.white : PieceColor.black,
        myOutcome: outcome,
        at: _now.subtract(Duration(hours: (46 - i) * 9 + rng.nextInt(5))),
      );
    }
  }

  Player _addPlayer(String name, String email) {
    final id = 'demo-${_players.length + 1}';
    final player = Player(
      id: id,
      displayName: _uniqueName(name),
      rating: startingRating,
      gamesPlayed: 0,
      wins: 0,
      losses: 0,
      draws: 0,
      design: 'chalkboard',
    );
    _players[id] = player;
    _emails[email.trim().toLowerCase()] = id;
    return player;
  }

  String _uniqueName(String base) {
    var candidate = base;
    var suffix = 1;
    bool taken(String n) =>
        _players.values.any((p) => p.displayName.toLowerCase() == n.toLowerCase());
    while (taken(candidate)) {
      suffix++;
      candidate = '$base $suffix';
    }
    return candidate;
  }

  ChessMatch _apply({
    required String me,
    required String opponentId,
    required PieceColor myColor,
    required Outcome myOutcome,
    required DateTime at,
  }) {
    final whiteId = myColor == PieceColor.white ? me : opponentId;
    final blackId = myColor == PieceColor.white ? opponentId : me;
    final white = _players[whiteId]!;
    final black = _players[blackId]!;
    final result = switch (myOutcome) {
      Outcome.draw => MatchResult.draw,
      Outcome.win =>
        myColor == PieceColor.white ? MatchResult.white : MatchResult.black,
      Outcome.loss =>
        myColor == PieceColor.white ? MatchResult.black : MatchResult.white,
    };
    final whiteScore = switch (result) {
      MatchResult.white => 1.0,
      MatchResult.black => 0.0,
      MatchResult.draw => 0.5,
    };
    final delta = eloDelta(white.rating, black.rating, whiteScore);

    _players[whiteId] = white.copyWith(
      rating: white.rating + delta,
      gamesPlayed: white.gamesPlayed + 1,
      wins: white.wins + (result == MatchResult.white ? 1 : 0),
      losses: white.losses + (result == MatchResult.black ? 1 : 0),
      draws: white.draws + (result == MatchResult.draw ? 1 : 0),
    );
    _players[blackId] = black.copyWith(
      rating: black.rating - delta,
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
      whiteRatingBefore: white.rating,
      blackRatingBefore: black.rating,
      ratingDelta: delta,
      playedAt: at,
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
        whiteRatingBefore: m.whiteRatingBefore,
        blackRatingBefore: m.blackRatingBefore,
        ratingDelta: m.ratingDelta,
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
    if (!key.contains('@')) throw const LadderException('Enter an email address.');
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
      throw const LadderException('That email already has an account. Sign in instead.');
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
  Future<ChessMatch> recordMatch({
    required String opponentId,
    required PieceColor myColor,
    required Outcome myOutcome,
  }) async {
    final me = _requireMe();
    if (opponentId == me.id) {
      throw const LadderException('Choose an opponent other than yourself.');
    }
    if (!_players.containsKey(opponentId)) {
      throw const LadderException('Opponent not found.');
    }
    final match = _apply(
      me: me.id,
      opponentId: opponentId,
      myColor: myColor,
      myOutcome: myOutcome,
      at: DateTime.now(),
    );
    _revision++;
    notifyListeners();
    return match;
  }

  @override
  Future<void> updateProfile({String? displayName, String? design}) async {
    final me = _requireMe();
    if (displayName != null) {
      final name = displayName.trim();
      final taken = _players.values.any(
          (p) => p.id != me.id && p.displayName.toLowerCase() == name.toLowerCase());
      if (taken) throw const LadderException('That name is taken. Try another.');
    }
    _players[me.id] = me.copyWith(displayName: displayName?.trim(), design: design);
    if (displayName != null) _revision++;
    notifyListeners();
  }
}
