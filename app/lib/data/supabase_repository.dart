import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import 'ladder_repository.dart';
import 'live_updates.dart';
import 'query_cache.dart';

/// A profile with its rating in every mode.
const _profileWithRatings = '*, ratings(*)';

/// The storage bucket holding each member's photo under their id.
const _avatarBucket = 'avatars';

/// A confirmed result with its players. Each keeps a copy of the player's
/// name, so the result outlives a deleted account.
const _resultColumns = '*, match_players(*)';

/// A request with its players and their live names (requests go with a
/// deleted account).
const _requestColumns = '*, match_request_players(*, profiles(display_name))';

/// Tables whose changes tell a member something is waiting for them, in
/// every game: every request change (new, answered, withdrawn), every
/// confirmation, and every confirmed result. Kept in step with the
/// publication in the migrations.
const _watched = [
  (table: 'match_requests', event: PostgresChangeEvent.all),
  (table: 'match_request_players', event: PostgresChangeEvent.all),
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
    _me = row == null ? null : _playerFrom(row);
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
      return rows.map(_playerFrom).toList();
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

  /// A profile row as a [Player], with the URL of their photo when they
  /// have one. The change time in the URL makes browsers drop a replaced
  /// photo they cached.
  Player _playerFrom(Map<String, dynamic> row) {
    final player = Player.fromRow(row);
    final changedAt = row['avatar_updated_at'] as String?;
    if (changedAt == null) return player;
    final url = _client.storage.from(_avatarBucket).getPublicUrl(player.id);
    return player.withAvatar(
      Uri.parse(url).replace(queryParameters: {'v': changedAt}).toString(),
    );
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AuthException catch (e) {
      throw LadderException(e.message);
    } on PostgrestException catch (e) {
      throw LadderException(e.message);
    } on StorageException catch (e) {
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

  @override
  Future<void> deleteAccount() => _guard(() async {
    // Storage refuses deletes from SQL, so the photo can't go with the
    // account; it would stay public under the member's id.
    if (_me?.avatarUrl != null) {
      await _client.storage.from(_avatarBucket).remove([_me!.id]);
    }
    await _client.rpc<void>('delete_my_account');
    // The user no longer exists, so the logout call is answered 403/404;
    // gotrue ignores that for the local scope, which only clears this
    // device's session.
    await _client.auth.signOut(scope: SignOutScope.local);
    _me = null;
    _recovering = false;
    _players = null;
    _queries.clear();
    notifyListeners();
  });

  @override
  Future<List<Player>> members() => _allPlayers();

  @override
  Future<Player> player(String id) async => (await _allPlayers()).firstWhere(
    (p) => p.id == id,
    orElse: () => throw const LadderException('That player no longer exists.'),
  );

  /// Shared per parameters until data changes, so switching tabs doesn't
  /// refetch.
  @override
  Future<List<GameResult>> results(
    MatchType type, {
    GameMode? mode,
    String? playerId,
    int limit = 50,
    DateTime? before,
  }) => _queries.of(
    ('matches', type, mode, playerId, limit, before),
    () => _guard(() async {
      // A member's results are found through a second, inner-joined copy of
      // the players, so the first still lists all of them.
      var query = _client
          .from('matches')
          .select(
            playerId == null
                ? _resultColumns
                : '$_resultColumns, played_by:match_players!inner(player_id)',
          )
          .eq('match_type', type.name);
      if (mode != null) query = query.eq('mode', mode.key);
      if (playerId != null) query = query.eq('played_by.player_id', playerId);
      if (before != null) {
        query = query.lt('played_at', before.toUtc().toIso8601String());
      }
      final rows = await query
          .order('played_at', ascending: false)
          .limit(limit);
      return rows.map(GameResult.fromRow).toList();
    }),
  );

  /// Limited to the signed-in member's by row level security.
  @override
  Future<List<ResultRequest>> requests() => _queries.of(
    ('match_requests',),
    () => _guard(() async {
      final rows = await _client
          .from('match_requests')
          .select(_requestColumns)
          .order('created_at', ascending: false);
      return rows.map(ResultRequest.fromRow).toList();
    }),
  );

  @override
  Future<ResultRequest> reportResult(ResultReport report) => _guard(() async {
    final clock = report.clock;
    final inserted = await _client.rpc<Map<String, dynamic>>(
      'request_match',
      params: {
        'p_match_type': report.mode.type.name,
        'p_mode': report.mode.key,
        'p_players': [
          for (final s in report.seats)
            {'player_id': s.playerId, 'side': s.side, 'score': s.score},
        ],
        'p_rated': report.rated,
        'p_dgt_option': clock?.preset.dgtOption,
        'p_custom_base_minutes': clock?.customBaseMinutes,
        'p_custom_extra_seconds': clock?.customExtraSeconds,
      },
    );
    final request = ResultRequest.fromRow(
      await _client
          .from('match_requests')
          .select(_requestColumns)
          .eq('id', inserted['id'] as int)
          .single(),
    );
    _dataChanged();
    return request;
  });

  @override
  Future<GameResult?> respondToRequest(int requestId, {required bool accept}) =>
      _guard(() async {
        final inserted = await _client.rpc<Map<String, dynamic>?>(
          'respond_to_match',
          params: {'p_request_id': requestId, 'p_accept': accept},
        );
        final matchId = inserted?['id'] as int?;
        final result = matchId == null
            ? null
            : GameResult.fromRow(
                await _client
                    .from('matches')
                    .select(_resultColumns)
                    .eq('id', matchId)
                    .single(),
              );
        if (result != null) await _loadMe();
        _dataChanged();
        return result;
      });

  @override
  Future<void> dismissRequest(int requestId) => _guard(() async {
    await _client.rpc<void>(
      'dismiss_declined_match',
      params: {'p_request_id': requestId},
    );
    _dataChanged();
  });

  @override
  Future<void> updateDisplayName(String displayName) => _guard(() async {
    try {
      await _updateMe({'display_name': displayName.trim()});
    } on PostgrestException catch (e) {
      throw LadderException(
        e.code == '23505' ? 'That name is taken. Try another.' : e.message,
      );
    }
  });

  @override
  Future<void> updateAvatar(Uint8List image, {required String contentType}) =>
      _guard(() async {
        await _client.storage
            .from(_avatarBucket)
            .uploadBinary(
              _requireMe().id,
              image,
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            );
        await _updateMe({
          'avatar_updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      });

  @override
  Future<void> removeAvatar() => _guard(() async {
    await _client.storage.from(_avatarBucket).remove([_requireMe().id]);
    await _updateMe({'avatar_updated_at': null});
  });

  Player _requireMe() =>
      _me ?? (throw const LadderException('Sign in to continue.'));

  /// Saves [changes] to the signed-in member's profile, then has every
  /// screen show it.
  Future<void> _updateMe(Map<String, dynamic> changes) async {
    // Returning the row makes an update that RLS silently skipped fail
    // instead of pretending to save.
    final row = await _client
        .from('profiles')
        .update(changes)
        .eq('id', _requireMe().id)
        .select(_profileWithRatings)
        .single();
    _me = _playerFrom(row);
    _dataChanged();
  }

  @override
  void dispose() {
    _live.stop();
    _authSub.cancel();
    super.dispose();
  }
}
