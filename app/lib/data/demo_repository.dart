import '../domain/models.dart';
import 'ladder_repository.dart';

/// In-memory ladder used when no Supabase project is configured.
///
/// Applies the same rules as the database so the app can be tried out
/// without a backend. Starts empty and lives only in this tab.
class DemoLadderRepository extends LadderRepository {
  final Map<String, Player> _players = {};
  final Map<String, String> _emails = {};
  final List<GameResult> _results = [];
  final List<ResultRequest> _requests = [];
  int _nextRequestId = 1;

  /// Never reused: a deleted member's id stays on their results, so a
  /// length-based id would hand it to the next sign-up.
  int _nextPlayerId = 1;
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
    final id = 'demo-${_nextPlayerId++}';
    final player = Player(id: id, displayName: _uniqueName(name));
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

  /// A pending request is read by its players, a declined one only by its
  /// reporter (as the database's policies have it).
  bool _visibleTo(String meId, ResultRequest r) =>
      r.involves(meId) &&
      (r.status == RequestStatus.pending || r.requestedBy == meId);

  /// Names follow renames; a deleted member's stay as they were when the
  /// account was deleted.
  GameResult _withCurrentNames(GameResult r) =>
      r.renamed((id) => _players[id]?.displayName);

  /// Rates [request] once everyone confirmed it, as respond_to_match does.
  GameResult _rate(ResultRequest request) {
    final mode = request.mode;
    final players = [for (final s in request.seats) _players[s.playerId]!];
    final standings = {for (final p in players) p.id: p.standingIn(mode)};
    final deltas = request.rated
        ? ratingChanges(mode, bestOf: request.bestOf, [
            for (final s in request.seats)
              (
                playerId: s.playerId,
                side: s.side,
                score: s.score,
                standing: standings[s.playerId]!,
              ),
          ])
        : {for (final p in players) p.id: 0};
    if (request.rated) {
      for (final p in players) {
        _players[p.id] = p.copyWith(
          standings: {
            ...p.standings,
            mode: standings[p.id]!.after(
              delta: deltas[p.id]!,
              outcome: request.outcomeFor(p.id),
              experienceGained: mode.type == MatchType.backgammon
                  ? request.matchLength
                  : 0,
            ),
          },
        );
      }
    }
    final result = GameResult(
      id: _results.length + 1,
      mode: mode,
      seats: [
        for (final s in request.seats)
          RatedSeat(
            playerId: s.playerId,
            name: _players[s.playerId]!.displayName,
            side: s.side,
            score: s.score,
            ratingBefore: standings[s.playerId]!.rating,
            ratingDelta: deltas[s.playerId]!,
          ),
      ],
      rated: request.rated,
      clock: request.clock,
      bestOf: request.bestOf,
      recordedBy: request.requestedBy,
      playedAt: DateTime.now(),
    );
    _results.add(result);
    return result;
  }

  void _changed() {
    _revision++;
    notifyListeners();
  }

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
  Future<void> deleteAccount() async {
    final me = _requireMe();
    // Confirmed results stay, under the name the member has now (as on the
    // server, which keeps each result's names in step with renames).
    _results.setAll(0, _results.map(_withCurrentNames).toList());
    _emails.removeWhere((_, id) => id == me.id);
    _players.remove(me.id);
    // Open requests go with any of their players.
    _requests.removeWhere((r) => r.involves(me.id));
    _revision++;
    await signOut();
  }

  @override
  Future<List<Player>> members() async => _players.values.toList();

  @override
  Future<Player> player(String id) async {
    final p = _players[id];
    if (p == null) throw const LadderException('That player no longer exists.');
    return p;
  }

  @override
  Future<List<GameResult>> results(
    MatchType type, {
    GameMode? mode,
    String? playerId,
    int limit = 50,
    DateTime? before,
  }) async => _results.reversed
      .where((r) => r.mode.type == type && (mode == null || r.mode == mode))
      .where((r) => playerId == null || r.involves(playerId))
      .where((r) => before == null || r.playedAt.isBefore(before))
      .take(limit)
      .map(_withCurrentNames)
      .toList();

  @override
  Future<ResultRequest> reportResult(ResultReport report) async {
    final me = _requireMe();
    final mode = report.mode;
    final reason = invalidResultReason(
      mode,
      report.seats,
      bestOf: report.bestOf,
    );
    if (reason != null) throw LadderException('$reason.');
    if (!report.seats.any((s) => s.playerId == me.id)) {
      throw const LadderException('Record a result you played in.');
    }
    final clock = report.clock;
    if (mode.type == MatchType.chess) {
      if (clock == null) {
        throw const LadderException('Pick the time control you played.');
      }
      if (!clock.isComplete) {
        throw const LadderException('Set the custom time you played.');
      }
    } else if (clock != null) {
      throw const LadderException('Only chess has time controls.');
    }
    if (report.seats.any((s) => !_players.containsKey(s.playerId))) {
      throw const LadderException('Player not found.');
    }
    final request = ResultRequest(
      id: _nextRequestId++,
      mode: mode,
      seats: [
        for (final s in report.seats)
          RequestSeat(
            playerId: s.playerId,
            name: _players[s.playerId]!.displayName,
            side: s.side,
            score: s.score,
            confirmed: s.playerId == me.id,
          ),
      ],
      rated: report.rated,
      clock: clock,
      bestOf: report.bestOf,
      requestedBy: me.id,
      createdAt: DateTime.now(),
    );
    _requests.add(request);
    _changed();
    return request;
  }

  @override
  Future<List<ResultRequest>> requests() async {
    final me = _requireMe();
    return _requests.reversed.where((r) => _visibleTo(me.id, r)).toList();
  }

  @override
  Future<GameResult?> respondToRequest(
    int requestId, {
    required bool accept,
  }) async {
    final me = _requireMe();
    final index = _requests.indexWhere(
      (r) =>
          r.id == requestId &&
          r.involves(me.id) &&
          r.status == RequestStatus.pending,
    );
    if (index < 0) {
      throw const LadderException(
        'That result is no longer waiting for confirmation.',
      );
    }
    final request = _requests[index];
    GameResult? result;
    if (!accept) {
      // Declining tells the reporter; withdrawing just removes it.
      if (request.requestedBy == me.id) {
        _requests.removeAt(index);
      } else {
        _requests[index] = request.declined(me.id, DateTime.now());
      }
    } else {
      if (request.requestedBy == me.id) {
        throw const LadderException(
          'The other players have to confirm this result.',
        );
      }
      final confirmed = request.confirmedBy(me.id);
      if (confirmed.waitingOn.isEmpty) {
        _requests.removeAt(index);
        result = _rate(confirmed);
      } else {
        _requests[index] = confirmed;
      }
    }
    _changed();
    return result;
  }

  @override
  Future<void> dismissRequest(int requestId) async {
    final me = _requireMe();
    final before = _requests.length;
    _requests.removeWhere((r) => r.id == requestId && r.declinedFor(me.id));
    if (_requests.length == before) {
      throw const LadderException(
        'That result is not waiting to be dismissed.',
      );
    }
    _changed();
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
    _changed();
  }
}
