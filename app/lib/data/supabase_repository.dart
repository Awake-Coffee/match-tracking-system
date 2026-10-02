import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import 'ladder_repository.dart';

const _matchSelect =
    '*, white:profiles!matches_white_id_fkey(display_name), '
    'black:profiles!matches_black_id_fkey(display_name)';

class SupabaseLadderRepository extends LadderRepository {
  SupabaseLadderRepository(this._client) {
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        _me = null;
        notifyListeners();
      } else if (state.session != null && _me?.id != state.session!.user.id) {
        unawaited(_loadMe());
      }
    });
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _authSub;
  Player? _me;
  int _revision = 0;

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
    final row =
        await _client.from('profiles').select().eq('id', user.id).maybeSingle();
    _me = row == null ? null : Player.fromRow(row);
    notifyListeners();
  }

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
        await _client.auth
            .signInWithPassword(email: email.trim(), password: password);
        await _loadMe();
      });

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) =>
      _guard(() async {
        final res = await _client.auth.signUp(
          email: email.trim(),
          password: password,
          data: {'display_name': displayName.trim()},
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

  @override
  Future<List<Player>> ladder() => _guard(() async {
        final rows = await _client
            .from('profiles')
            .select()
            .order('rating', ascending: false)
            .order('games_played', ascending: false)
            .order('display_name');
        return rows.map(Player.fromRow).toList();
      });

  @override
  Future<Player> player(String id) => _guard(() async {
        final row = await _client.from('profiles').select().eq('id', id).single();
        return Player.fromRow(row);
      });

  @override
  Future<List<ChessMatch>> matches({String? playerId, int limit = 50}) =>
      _guard(() async {
        var query = _client.from('matches').select(_matchSelect);
        if (playerId != null) {
          query = query.or('white_id.eq.$playerId,black_id.eq.$playerId');
        }
        final rows =
            await query.order('played_at', ascending: false).limit(limit);
        return rows.map(ChessMatch.fromRow).toList();
      });

  @override
  Future<ChessMatch> recordMatch({
    required String opponentId,
    required PieceColor myColor,
    required Outcome myOutcome,
  }) =>
      _guard(() async {
        final inserted = await _client.rpc<Map<String, dynamic>>(
          'record_chess_match',
          params: {
            'p_opponent_id': opponentId,
            'p_my_color': myColor.name,
            'p_my_result': myOutcome.name,
          },
        );
        final row = await _client
            .from('matches')
            .select(_matchSelect)
            .eq('id', inserted['id'] as int)
            .single();
        await _loadMe();
        _revision++;
        notifyListeners();
        return ChessMatch.fromRow(row);
      });

  @override
  Future<void> updateProfile({String? displayName, String? design}) =>
      _guard(() async {
        final me = _me;
        if (me == null) return;
        final changes = <String, dynamic>{
          'display_name': ?displayName?.trim(),
          'design': ?design,
        };
        if (changes.isEmpty) return;
        // Apply locally first so a design switch is instant.
        _me = me.copyWith(displayName: displayName?.trim(), design: design);
        notifyListeners();
        try {
          await _client.from('profiles').update(changes).eq('id', me.id);
        } on PostgrestException catch (e) {
          _me = me;
          notifyListeners();
          throw LadderException(
            e.code == '23505' ? 'That name is taken. Try another.' : e.message,
          );
        }
        if (displayName != null) {
          _revision++;
          notifyListeners();
        }
      });

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }
}
