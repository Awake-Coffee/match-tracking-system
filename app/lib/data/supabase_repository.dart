import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/backgammon.dart';
import '../domain/models.dart';
import '../domain/swu.dart';
import 'ladder_repository.dart';
import 'live_updates.dart';
import 'query_cache.dart';

/// One game's rows in the shared `matches` or `match_requests` table: the
/// table, the game's `match_type` and how to read a row.
typedef _ResultTable<T> = ({
  String name,
  String matchType,
  T Function(Map<String, dynamic>) fromRow,
});

final _ResultTable<ChessMatch> _chessMatches = (
  name: 'matches',
  matchType: 'chess',
  fromRow: ChessMatch.fromRow,
);
final _ResultTable<MatchRequest> _chessRequests = (
  name: 'match_requests',
  matchType: 'chess',
  fromRow: MatchRequest.fromRow,
);
final _ResultTable<BackgammonMatch> _backgammonMatches = (
  name: 'matches',
  matchType: 'backgammon',
  fromRow: BackgammonMatch.fromRow,
);
final _ResultTable<BackgammonMatchRequest> _backgammonRequests = (
  name: 'match_requests',
  matchType: 'backgammon',
  fromRow: BackgammonMatchRequest.fromRow,
);
final _ResultTable<SwuMatch> _swuMatches = (
  name: 'matches',
  matchType: 'swu',
  fromRow: SwuMatch.fromRow,
);
final _ResultTable<SwuMatchRequest> _swuRequests = (
  name: 'match_requests',
  matchType: 'swu',
  fromRow: SwuMatchRequest.fromRow,
);

/// Every column plus both players' display names, embedded under the side.
String _selectWithNames<T>(_ResultTable<T> table) =>
    '*, $player1:profiles!${table.name}_${player1}_id_fkey(display_name), '
    '$player2:profiles!${table.name}_${player2}_id_fkey(display_name)';

/// A profile with its rating in every game.
const _profileWithRatings = '*, ratings(*)';

/// Tables whose changes tell a member something is waiting for them, in
/// every game: every request change (new, answered, withdrawn) and every
/// confirmed result. Kept in step with the publication in the realtime
/// migration.
const _watched = [
  (table: 'match_requests', event: PostgresChangeEvent.all),
  (table: 'matches', event: PostgresChangeEvent.insert),
];

class SupabaseLadderRepository extends LadderRepository {
  SupabaseLadderRepository(this._client) {
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        // The link has already signed the member in; the router sends them to
        // choose a password before anything else.
        _recovering = true;
        _authLinkError = null;
        notifyListeners();
      }
      if (state.event == AuthChangeEvent.signedOut) {
        _me = null;
        _recovering = false;
        _queries.clear();
        _live.stop();
        notifyListeners();
        // initialSession is left to restore(), so startup fetches the profile once.
      } else if (state.event != AuthChangeEvent.initialSession &&
          state.session != null &&
          _me?.id != state.session!.user.id) {
        unawaited(_loadMe());
      }
    }, onError: _authLinkFailed);
  }

  /// supabase_flutter turns a reset link it can't use (expired, already used,
  /// or missing its PKCE code verifier because it was opened in another
  /// browser) into an error on the auth stream, which replays it to us.
  /// Other auth errors (a refresh failing offline) are not about a link.
  void _authLinkFailed(Object error) {
    if (error is! AuthException || error is AuthRetryableFetchException) return;
    if (!_openedFromResetLink) return;
    _authLinkError = brokenResetLinkMessage;
    notifyListeners();
  }

  /// Whether this page load is the reset link's redirect: its path plus the
  /// auth parameters supabase_flutter reads (cleared only on success). Read
  /// at startup, before the router rewrites the address.
  final bool _openedFromResetLink = kIsWeb && _isResetRedirect(Uri.base);

  static bool _isResetRedirect(Uri url) {
    if (url.path != '/reset-password') return false;
    // Keys only, undecoded: a malformed value must not break startup.
    final keys = '${url.query}&${url.fragment}'
        .split('&')
        .map((pair) => pair.split('=').first)
        .toSet();
    return const [
      'code',
      'error',
      'error_code',
      'error_description',
    ].any(keys.contains);
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _authSub;
  Player? _me;
  bool _recovering = false;
  String? _authLinkError;
  int _revision = 0;
  Future<List<Player>>? _players;

  /// Matches and request lists by table and parameters, kept like [_players].
  final _queries = QueryCache();
  late final _live = LiveUpdates(onChanged: _dataChanged, subscribe: _listen);

  @override
  Player? get me => _me;

  @override
  int get revision => _revision;

  @override
  String? get email => _client.auth.currentUser?.email;

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

  /// Loads the profile for an existing session (call once at startup).
  Future<void> restore() async {
    if (_client.auth.currentSession != null) await _loadMe();
  }

  Future<void> _loadMe() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final row = await _client
        .from('profiles')
        .select(_profileWithRatings)
        .eq('id', user.id)
        .maybeSingle();
    _me = row == null ? null : Player.fromRow(row);
    // A new account isn't in the cached members yet, and requests are
    // visible per member.
    _players = null;
    _queries.clear();
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
    _queries.clear();
    notifyListeners();
  }

  @override
  void reload() => _dataChanged();

  /// Every member, fetched once and shared by all ladders and profiles until
  /// data changes.
  Future<List<Player>> _allPlayers() {
    if (_players case final cached?) return cached;
    final fetch = _guard(() async {
      final rows = await _client.from('profiles').select(_profileWithRatings);
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
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required String displayName,
  }) => _guard(() async {
    final res = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': displayName.trim()},
      emailRedirectTo: _confirmationRedirect,
    );
    // No session means the project requires email confirmation first.
    if (res.session == null) return SignUpResult.confirmationSent;
    await _loadMe();
    return SignUpResult.signedIn;
  });

  /// Without it the confirmation link opens Supabase's Site URL, whatever
  /// host the member signed up on. Must be in the project's Redirect URLs.
  String? get _confirmationRedirect => kIsWeb ? '${Uri.base.origin}/' : null;

  /// Where the password-reset link lands. Must be in the Redirect URLs too.
  String? get _recoveryRedirect =>
      kIsWeb ? '${Uri.base.origin}/reset-password' : null;

  /// Auth emails to one address are rate limited; the raw "only request this
  /// after N seconds" reads as alarming.
  bool _isEmailRateLimit(AuthException e) =>
      e.statusCode == '429' || e.code == 'over_email_send_rate_limit';

  @override
  Future<void> resendSignUpConfirmation(String email) => _guard(() async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: _confirmationRedirect,
      );
    } on AuthException catch (e) {
      // The sign-up email counts too, so an early resend is refused.
      if (_isEmailRateLimit(e)) {
        throw const LadderException('Give it a minute, then try again.');
      }
      rethrow;
    }
  });

  @override
  Future<void> sendPasswordReset(String email) => _guard(() async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: _recoveryRedirect,
      );
    } on AuthException catch (e) {
      if (_isEmailRateLimit(e)) {
        throw const LadderException('Give it a minute, then try again.');
      }
      rethrow;
    }
  });

  @override
  Future<void> updatePassword(String newPassword) => _guard(() async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
    // The recovery event can beat the profile fetch; the ladder needs it.
    if (_me == null) await _loadMe();
    _recovering = false;
    notifyListeners();
  });

  @override
  Future<void> signOut() => _guard(() async {
    await _client.auth.signOut();
    _me = null;
    _recovering = false;
    _queries.clear();
    notifyListeners();
  });

  /// Newest first; only [playerId]'s when set, and only those whose
  /// [orderColumn] is before [before] when set (the next page). Pending
  /// requests are already limited to the signed-in member by RLS. Shared per
  /// parameters until data changes, so switching tabs doesn't refetch.
  Future<List<T>> _results<T>(
    _ResultTable<T> table, {
    required String orderColumn,
    String? playerId,
    int? limit,
    DateTime? before,
  }) => _queries.of(
    // Games share a table, so the game is part of the key.
    (table.name, table.matchType, playerId, limit, before),
    () => _guard(() async {
      var query = _client
          .from(table.name)
          .select(_selectWithNames(table))
          .eq('match_type', table.matchType);
      if (playerId != null) {
        query = query.or(
          '${player1}_id.eq.$playerId,${player2}_id.eq.$playerId',
        );
      }
      final older = before == null
          ? query
          : query.lt(orderColumn, before.toUtc().toIso8601String());
      final ordered = older.order(orderColumn, ascending: false);
      final rows = await (limit == null ? ordered : ordered.limit(limit));
      return rows.map(table.fromRow).toList();
    }),
  );

  Future<T> _rowById<T>(_ResultTable<T> table, int id) async => table.fromRow(
    await _client
        .from(table.name)
        .select(_selectWithNames(table))
        .eq('id', id)
        .single(),
  );

  /// Reports a result with `request_match` and returns the stored request
  /// with names. [params] are the game's own: scores, and for chess the
  /// color and clock.
  Future<T> _request<T>(
    _ResultTable<T> requests,
    Map<String, dynamic> params, {
    required bool rated,
  }) => _guard(() async {
    final inserted = await _client.rpc<Map<String, dynamic>>(
      'request_match',
      params: {'p_match_type': requests.matchType, 'p_rated': rated, ...params},
    );
    final request = await _rowById(requests, inserted['id'] as int);
    _dataChanged();
    return request;
  });

  /// Answers a request with `respond_to_match`; returns the confirmed
  /// result, or null when the request was dropped.
  Future<T?> _respond<T>(int requestId, bool accept, _ResultTable<T> matches) =>
      _guard(() async {
        final inserted = await _client.rpc<Map<String, dynamic>?>(
          'respond_to_match',
          params: {'p_request_id': requestId, 'p_accept': accept},
        );
        final matchId = inserted?['id'] as int?;
        final match = matchId == null ? null : await _rowById(matches, matchId);
        if (match != null) await _loadMe();
        _dataChanged();
        return match;
      });

  /// The reporter clears a declined request with `dismiss_declined_match`.
  Future<void> _dismiss(int requestId) => _guard(() async {
    await _client.rpc<void>(
      'dismiss_declined_match',
      params: {'p_request_id': requestId},
    );
    _dataChanged();
  });

  @override
  Future<Player> player(String id) async => (await _allPlayers()).firstWhere(
    (p) => p.id == id,
    orElse: () => throw const LadderException('That player no longer exists.'),
  );

  @override
  Future<List<Player>> ladder() => _ladderBy(compareLadder);

  @override
  Future<List<ChessMatch>> matches({
    String? playerId,
    int limit = 50,
    DateTime? before,
  }) => _results(
    _chessMatches,
    orderColumn: 'played_at',
    playerId: playerId,
    limit: limit,
    before: before,
  );

  @override
  Future<MatchRequest> requestMatch({
    required String opponentId,
    required PieceColor myColor,
    required Outcome myOutcome,
    required ClockSetting clock,
    bool rated = true,
  }) => _request(_chessRequests, {
    'p_opponent_id': opponentId,
    'p_my_score': myOutcome.score,
    'p_opponent_score': 1 - myOutcome.score,
    'p_my_color': myColor.name,
    'p_dgt_option': clock.preset.dgtOption,
    'p_custom_base_minutes': clock.customBaseMinutes,
    'p_custom_extra_seconds': clock.customExtraSeconds,
  }, rated: rated);

  @override
  Future<List<MatchRequest>> matchRequests() =>
      _results(_chessRequests, orderColumn: 'created_at');

  @override
  Future<ChessMatch?> respondToMatchRequest(
    int requestId, {
    required bool accept,
  }) => _respond(requestId, accept, _chessMatches);

  @override
  Future<void> dismissMatchRequest(int requestId) => _dismiss(requestId);

  @override
  Future<List<Player>> backgammonLadder() => _ladderBy(compareBackgammonLadder);

  @override
  Future<List<BackgammonMatch>> backgammonMatches({
    String? playerId,
    int limit = 50,
    DateTime? before,
  }) => _results(
    _backgammonMatches,
    orderColumn: 'played_at',
    playerId: playerId,
    limit: limit,
    before: before,
  );

  @override
  Future<BackgammonMatchRequest> requestBackgammonMatch({
    required String opponentId,
    required int matchLength,
    required int myScore,
    required int opponentScore,
    bool rated = true,
  }) {
    // The database reads the match length off the winner's score.
    if (!isFinalScore(matchLength, myScore, opponentScore)) {
      return Future.error(
        const LadderException(
          'The winner\'s score must equal the match length',
        ),
      );
    }
    return _request(_backgammonRequests, {
      'p_opponent_id': opponentId,
      'p_my_score': myScore,
      'p_opponent_score': opponentScore,
    }, rated: rated);
  }

  @override
  Future<List<BackgammonMatchRequest>> backgammonMatchRequests() =>
      _results(_backgammonRequests, orderColumn: 'created_at');

  @override
  Future<BackgammonMatch?> respondToBackgammonMatchRequest(
    int requestId, {
    required bool accept,
  }) => _respond(requestId, accept, _backgammonMatches);

  @override
  Future<void> dismissBackgammonMatchRequest(int requestId) =>
      _dismiss(requestId);

  @override
  Future<List<Player>> swuLadder() => _ladderBy(compareSwuLadder);

  @override
  Future<List<SwuMatch>> swuMatches({
    String? playerId,
    int limit = 50,
    DateTime? before,
  }) => _results(
    _swuMatches,
    orderColumn: 'played_at',
    playerId: playerId,
    limit: limit,
    before: before,
  );

  @override
  Future<SwuMatchRequest> requestSwuMatch({
    required String opponentId,
    required int myGames,
    required int opponentGames,
    bool rated = true,
  }) => _request(_swuRequests, {
    'p_opponent_id': opponentId,
    'p_my_score': myGames,
    'p_opponent_score': opponentGames,
  }, rated: rated);

  @override
  Future<List<SwuMatchRequest>> swuMatchRequests() =>
      _results(_swuRequests, orderColumn: 'created_at');

  @override
  Future<SwuMatch?> respondToSwuMatchRequest(
    int requestId, {
    required bool accept,
  }) => _respond(requestId, accept, _swuMatches);

  @override
  Future<void> dismissSwuMatchRequest(int requestId) => _dismiss(requestId);

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
          .select(_profileWithRatings)
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
