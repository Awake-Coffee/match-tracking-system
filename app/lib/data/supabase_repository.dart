import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/backgammon.dart';
import '../domain/models.dart';
import '../domain/swu.dart';
import 'ladder_repository.dart';
import 'live_updates.dart';

/// A table of one game's results: its name, the two player columns
/// (`<side>_id`) and how to read a row.
typedef _ResultTable<T> = ({
  String name,
  (String, String) sides,
  T Function(Map<String, dynamic>) fromRow,
});

final _ResultTable<ChessMatch> _chessMatches = (
  name: 'matches',
  sides: ('white', 'black'),
  fromRow: ChessMatch.fromRow,
);
final _ResultTable<MatchRequest> _chessRequests = (
  name: 'match_requests',
  sides: ('white', 'black'),
  fromRow: MatchRequest.fromRow,
);
final _ResultTable<BackgammonMatch> _backgammonMatches = (
  name: 'backgammon_matches',
  sides: ('winner', 'loser'),
  fromRow: BackgammonMatch.fromRow,
);
final _ResultTable<BackgammonMatchRequest> _backgammonRequests = (
  name: 'backgammon_match_requests',
  sides: ('winner', 'loser'),
  fromRow: BackgammonMatchRequest.fromRow,
);
final _ResultTable<SwuMatch> _swuMatches = (
  name: 'swu_matches',
  sides: ('reporter', 'respondent'),
  fromRow: SwuMatch.fromRow,
);
final _ResultTable<SwuMatchRequest> _swuRequests = (
  name: 'swu_match_requests',
  sides: ('reporter', 'respondent'),
  fromRow: SwuMatchRequest.fromRow,
);

/// Every column plus both players' display names, embedded under the side.
String _selectWithNames<T>(_ResultTable<T> table) {
  final (first, second) = table.sides;
  return '*, $first:profiles!${table.name}_${first}_id_fkey(display_name), '
      '$second:profiles!${table.name}_${second}_id_fkey(display_name)';
}

/// Tables whose changes tell a member something is waiting for them: every
/// request change (new, answered, withdrawn) and every confirmed result.
/// Kept in step with the publication in the realtime migration.
const _watched = [
  (table: 'match_requests', event: PostgresChangeEvent.all),
  (table: 'backgammon_match_requests', event: PostgresChangeEvent.all),
  (table: 'swu_match_requests', event: PostgresChangeEvent.all),
  (table: 'matches', event: PostgresChangeEvent.insert),
  (table: 'backgammon_matches', event: PostgresChangeEvent.insert),
  (table: 'swu_matches', event: PostgresChangeEvent.insert),
];

class SupabaseLadderRepository extends LadderRepository {
  SupabaseLadderRepository(this._client) {
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        _me = null;
        _live.stop();
        notifyListeners();
        // initialSession is left to restore(), so startup fetches the profile once.
      } else if (state.event != AuthChangeEvent.initialSession &&
          state.session != null &&
          _me?.id != state.session!.user.id) {
        unawaited(_loadMe());
      }
    });
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _authSub;
  Player? _me;
  int _revision = 0;
  Future<List<Player>>? _players;
  late final _live = LiveUpdates(onChanged: _dataChanged, subscribe: _listen);

  @override
  Player? get me => _me;

  @override
  int get revision => _revision;

  /// Loads the profile for an existing session (call once at startup).
  Future<void> restore() async {
    if (_client.auth.currentSession != null) await _loadMe();
  }

  Future<void> _loadMe() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    _me = row == null ? null : Player.fromRow(row);
    // A new account isn't in the cached members yet.
    _players = null;
    if (_me != null) _live.start();
    notifyListeners();
  }

  /// Hears of other members' results and requests the moment they happen.
  VoidCallback _listen(VoidCallback onEvent) {
    final channel = _client.channel('ladder-changes');
    for (final (:table, :event) in _watched) {
      channel.onPostgresChanges(
        event: event,
        schema: 'public',
        table: table,
        callback: (_) => onEvent(),
      );
    }
    channel.subscribe();
    return () => unawaited(_client.removeChannel(channel));
  }

  /// Ratings, matches or pending games changed: screens reload, members refetch.
  void _dataChanged() {
    _revision++;
    _players = null;
    notifyListeners();
  }

  @override
  void reload() => _dataChanged();

  /// Every member, fetched once and shared by all ladders and profiles until
  /// data changes.
  Future<List<Player>> _allPlayers() {
    if (_players case final cached?) return cached;
    final fetch = _guard(() async {
      final rows = await _client.from('profiles').select();
      return rows.map(Player.fromRow).toList();
    });
    // A failure isn't kept, so the next load retries.
    fetch.then(
      (_) {},
      onError: (Object _) {
        if (identical(_players, fetch)) _players = null;
      },
    );
    return _players = fetch;
  }

  Future<List<Player>> _ladderBy(Comparator<Player> order) async =>
      (await _allPlayers()).toList()..sort(order);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AuthException catch (e) {
      throw LadderException(e.message);
    } on PostgrestException catch (e) {
      throw LadderException(e.message);
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard(() async {
        await _client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
        await _loadMe();
      });

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) => _guard(() async {
    final res = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': displayName.trim()},
      // Without it the confirmation link opens Supabase's Site URL, whatever
      // host the member signed up on. Must be in the project's Redirect URLs.
      emailRedirectTo: kIsWeb ? '${Uri.base.origin}/' : null,
    );
    if (res.session == null) {
      throw const LadderException(
        'Check your inbox to confirm your email, then sign in.',
      );
    }
    await _loadMe();
  });

  @override
  Future<void> signOut() => _guard(() async {
    await _client.auth.signOut();
    _me = null;
    notifyListeners();
  });

  /// Newest first; only [playerId]'s when set. Pending requests are already
  /// limited to the signed-in member by RLS.
  Future<List<T>> _results<T>(
    _ResultTable<T> table, {
    required String orderColumn,
    String? playerId,
    int? limit,
  }) => _guard(() async {
    var query = _client.from(table.name).select(_selectWithNames(table));
    if (playerId != null) {
      final (first, second) = table.sides;
      query = query.or('${first}_id.eq.$playerId,${second}_id.eq.$playerId');
    }
    final ordered = query.order(orderColumn, ascending: false);
    final rows = await (limit == null ? ordered : ordered.limit(limit));
    return rows.map(table.fromRow).toList();
  });

  Future<T> _rowById<T>(_ResultTable<T> table, int id) async => table.fromRow(
    await _client
        .from(table.name)
        .select(_selectWithNames(table))
        .eq('id', id)
        .single(),
  );

  /// Calls a game's request RPC and returns the stored request with names.
  Future<T> _request<T>(
    String rpc,
    Map<String, dynamic> params,
    _ResultTable<T> requests,
  ) => _guard(() async {
    final inserted = await _client.rpc<Map<String, dynamic>>(
      rpc,
      params: params,
    );
    final request = await _rowById(requests, inserted['id'] as int);
    _dataChanged();
    return request;
  });

  /// Calls a game's respond RPC; returns the confirmed result, or null when
  /// the request was dropped.
  Future<T?> _respond<T>(
    String rpc,
    int requestId,
    bool accept,
    _ResultTable<T> matches,
  ) => _guard(() async {
    final inserted = await _client.rpc<Map<String, dynamic>?>(
      rpc,
      params: {'p_request_id': requestId, 'p_accept': accept},
    );
    final matchId = inserted?['id'] as int?;
    final match = matchId == null ? null : await _rowById(matches, matchId);
    if (match != null) await _loadMe();
    _dataChanged();
    return match;
  });

  @override
  Future<Player> player(String id) async => (await _allPlayers()).firstWhere(
    (p) => p.id == id,
    orElse: () => throw const LadderException('That player no longer exists.'),
  );

  @override
  Future<List<Player>> ladder() => _ladderBy(compareLadder);

  @override
  Future<List<ChessMatch>> matches({String? playerId, int limit = 50}) =>
      _results(
        _chessMatches,
        orderColumn: 'played_at',
        playerId: playerId,
        limit: limit,
      );

  @override
  Future<MatchRequest> requestMatch({
    required String opponentId,
    required PieceColor myColor,
    required Outcome myOutcome,
    required ClockSetting clock,
    bool rated = true,
  }) => _request('request_chess_match', {
    'p_opponent_id': opponentId,
    'p_my_color': myColor.name,
    'p_my_result': myOutcome.name,
    'p_dgt_option': clock.preset.dgtOption,
    'p_custom_base_minutes': clock.customBaseMinutes,
    'p_custom_extra_seconds': clock.customExtraSeconds,
    'p_rated': rated,
  }, _chessRequests);

  @override
  Future<List<MatchRequest>> matchRequests() =>
      _results(_chessRequests, orderColumn: 'created_at');

  @override
  Future<ChessMatch?> respondToMatchRequest(
    int requestId, {
    required bool accept,
  }) => _respond('respond_to_chess_match', requestId, accept, _chessMatches);

  @override
  Future<List<Player>> backgammonLadder() => _ladderBy(compareBackgammonLadder);

  @override
  Future<List<BackgammonMatch>> backgammonMatches({
    String? playerId,
    int limit = 50,
  }) => _results(
    _backgammonMatches,
    orderColumn: 'played_at',
    playerId: playerId,
    limit: limit,
  );

  @override
  Future<BackgammonMatchRequest> requestBackgammonMatch({
    required String opponentId,
    required int matchLength,
    required int myScore,
    required int opponentScore,
    bool rated = true,
  }) => _request('request_backgammon_match', {
    'p_opponent_id': opponentId,
    'p_match_length': matchLength,
    'p_my_score': myScore,
    'p_opponent_score': opponentScore,
    'p_rated': rated,
  }, _backgammonRequests);

  @override
  Future<List<BackgammonMatchRequest>> backgammonMatchRequests() =>
      _results(_backgammonRequests, orderColumn: 'created_at');

  @override
  Future<BackgammonMatch?> respondToBackgammonMatchRequest(
    int requestId, {
    required bool accept,
  }) => _respond(
    'respond_to_backgammon_match',
    requestId,
    accept,
    _backgammonMatches,
  );

  @override
  Future<List<Player>> swuLadder() => _ladderBy(compareSwuLadder);

  @override
  Future<List<SwuMatch>> swuMatches({String? playerId, int limit = 50}) =>
      _results(
        _swuMatches,
        orderColumn: 'played_at',
        playerId: playerId,
        limit: limit,
      );

  @override
  Future<SwuMatchRequest> requestSwuMatch({
    required String opponentId,
    required int myGames,
    required int opponentGames,
    bool rated = true,
  }) => _request('request_swu_match', {
    'p_opponent_id': opponentId,
    'p_my_games': myGames,
    'p_opponent_games': opponentGames,
    'p_rated': rated,
  }, _swuRequests);

  @override
  Future<List<SwuMatchRequest>> swuMatchRequests() =>
      _results(_swuRequests, orderColumn: 'created_at');

  @override
  Future<SwuMatch?> respondToSwuMatchRequest(
    int requestId, {
    required bool accept,
  }) => _respond('respond_to_swu_match', requestId, accept, _swuMatches);

  @override
  Future<void> updateDisplayName(String displayName) => _guard(() async {
    final me = _me;
    if (me == null) throw const LadderException('Sign in to continue.');
    try {
      // Returning the row makes an update that RLS silently skipped fail
      // instead of pretending to save.
      final row = await _client
          .from('profiles')
          .update({'display_name': displayName.trim()})
          .eq('id', me.id)
          .select()
          .single();
      _me = Player.fromRow(row);
    } on PostgrestException catch (e) {
      throw LadderException(
        e.code == '23505' ? 'That name is taken. Try another.' : e.message,
      );
    }
    _dataChanged();
  });

  @override
  void dispose() {
    _live.stop();
    _authSub.cancel();
    super.dispose();
  }
}
