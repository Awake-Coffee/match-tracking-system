import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/ladder_repository.dart';
import 'design/design_scope.dart';
import 'design/design_spec.dart';
import 'domain/models.dart';
import 'ui/app_scope.dart';
import 'ui/game.dart';
import 'ui/navigation.dart';
import 'ui/screens/history_screen.dart';
import 'ui/screens/ladder_screen.dart';
import 'ui/screens/not_found_screen.dart';
import 'ui/screens/profile_screen.dart';
import 'ui/screens/record_screen.dart';
import 'ui/screens/reset_password_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/sign_in_screen.dart';
import 'ui/shell.dart';

class AwakeApp extends StatefulWidget {
  const AwakeApp({
    super.key,
    required this.repository,
    this.initialLocation = '/',
  });

  final LadderRepository repository;
  final String initialLocation;

  @override
  State<AwakeApp> createState() => _AwakeAppState();
}

typedef _Access = ({bool signedIn, bool recovering});

class _AwakeAppState extends State<AwakeApp> {
  late final GoRouter _router = _buildRouter();

  /// Whether the member was signed in at the last redirect, to tell signing
  /// out from arriving signed out.
  bool _wasSignedIn = false;

  /// What the redirect decides by, as of the last change to the repository.
  late _Access _access;
  final _themes = <DesignSpec, ThemeData>{};

  /// [game]'s design under the system's current light or dark setting.
  static DesignSpec _designOf(Game game, BuildContext context) =>
      game.designFor(MediaQuery.platformBrightnessOf(context));

  ThemeData _themeOf(DesignSpec spec) =>
      _themes.putIfAbsent(spec, spec.toTheme);

  LadderRepository get _repo => widget.repository;

  _Access get _accessNow =>
      (signedIn: _repo.isSignedIn, recovering: _repo.passwordRecoveryPending);

  @override
  void initState() {
    super.initState();
    _access = _accessNow;
    _repo.addListener(_repositoryChanged);
  }

  /// Re-runs the redirect for the repository's news. Signing in or out
  /// replaces the browser's current entry rather than adding one, so the
  /// sign-in page doesn't sit behind the page it led to, where Back would
  /// only bounce off it.
  void _repositoryChanged() {
    final access = _accessNow;
    final context = _router.routerDelegate.navigatorKey.currentContext;
    if (access == _access || context == null) {
      _router.refresh();
      return;
    }
    _access = access;
    Router.neglect(context, _router.refresh);
  }

  GoRouter _buildRouter() => GoRouter(
    initialLocation: widget.initialLocation,
    redirect: (context, state) {
      final wasSignedIn = _wasSignedIn;
      _wasSignedIn = _repo.isSignedIn;
      final onSignIn = state.matchedLocation == '/sign-in';
      final onReset = state.matchedLocation == '/reset-password';
      // The recovery link signs the member in only to choose a new password.
      if (_repo.passwordRecoveryPending) {
        return onReset ? null : '/reset-password';
      }
      // Signed in without a pending recovery (a reload, or a restored tab,
      // forgets the flag): stay, since the member may not know their password.
      if (onReset) return _repo.isSignedIn ? null : '/sign-in';
      if (!_repo.isSignedIn) {
        if (onSignIn) return null;
        // A link opened signed out is where signing in leads. Signing out
        // starts afresh rather than returning to the page it was done from.
        if (wasSignedIn || state.uri.path == '/') return '/sign-in';
        return Uri(
          path: '/sign-in',
          queryParameters: {'from': state.uri.toString()},
        ).toString();
      }
      if (onSignIn) return returnPath(state.uri.queryParameters['from']) ?? '/';
      return null;
    },
    // Unknown addresses match the catch-all route below; this is for what
    // the router itself can't resolve, such as a redirect loop.
    errorPageBuilder: (context, state) => NoTransitionPage(
      key: state.pageKey,
      child: const Scaffold(body: NotFoundScreen(game: Game.chess)),
    ),
    routes: [
      GoRoute(
        path: '/sign-in',
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: const SignInScreen()),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) => NoTransitionPage(
          key: state.pageKey,
          child: const ResetPasswordScreen(),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final game = Game.at(state.uri.path);
          final spec = _designOf(game, context);
          return DesignScope(
            spec: spec,
            child: Theme(
              data: _themeOf(spec),
              child: AppShell(
                game: game,
                location: state.uri.path,
                child: child,
              ),
            ),
          );
        },
        routes: [
          for (final game in Game.values) ..._gameRoutes(game),
          // Last, so it only catches what no page matched. A page of its own
          // rather than the router's error page, which would leave the
          // address bar on the previous address.
          GoRoute(
            path: '/:unknown(.*)',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: NotFoundScreen(game: Game.at(state.uri.path)),
            ),
          ),
        ],
      ),
    ],
  );

  /// The mode of [game] a page was opened for (`?mode=` or `:mode`), if
  /// it names one.
  GameMode? _mode(Game game, String? key) =>
      game.modes.where((m) => m.key == key).firstOrNull;

  /// The same pages for each game, under its own prefix.
  List<RouteBase> _gameRoutes(Game game) => [
    GoRoute(
      path: game.path(),
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: LadderScreen(game: game),
      ),
    ),
    GoRoute(
      path: game.path('ladder/:mode'),
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: switch (_mode(game, state.pathParameters['mode'])) {
          final mode? => ModeLadderScreen(mode: mode),
          null => NotFoundScreen(game: game),
        },
      ),
    ),
    GoRoute(
      path: game.path('record'),
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: RecordScreen(
          game: game,
          initialOpponentId: state.uri.queryParameters['opponent'],
          initialMode: _mode(game, state.uri.queryParameters['mode']),
        ),
      ),
    ),
    GoRoute(
      path: game.path('history'),
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: HistoryScreen(
          game: game,
          playerId: state.uri.queryParameters['player'],
        ),
      ),
    ),
    GoRoute(
      path: game.path('me'),
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: ProfileScreen(
          game: game,
          playerId: _repo.me!.id,
          isMe: true,
          initialMode: _mode(game, state.uri.queryParameters['mode']),
        ),
      ),
    ),
    GoRoute(
      path: game.path('settings'),
      pageBuilder: (context, state) =>
          NoTransitionPage(key: state.pageKey, child: const SettingsScreen()),
    ),
    GoRoute(
      path: game.path('players/:id'),
      pageBuilder: (context, state) {
        final id = state.pathParameters['id']!;
        final mode = _mode(game, state.uri.queryParameters['mode']);
        return NoTransitionPage(
          key: state.pageKey,
          child: ProfileScreen(
            key: ValueKey((game, id, mode)),
            game: game,
            playerId: id,
            isMe: id == _repo.me?.id,
            initialMode: mode,
          ),
        );
      },
    ),
  ];

  @override
  void dispose() {
    _repo.removeListener(_repositoryChanged);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      repository: _repo,
      child: MaterialApp.router(
        title: 'Awake Ladder',
        debugShowCheckedModeBanner: false,
        // Signed-out pages and dialogs wear chess, light or dark with the
        // system.
        theme: _themeOf(Game.chess.designFor(Brightness.light)),
        darkTheme: _themeOf(Game.chess.designFor(Brightness.dark)),
        routerConfig: _router,
        builder: (context, child) =>
            DesignScope(spec: _designOf(Game.chess, context), child: child!),
      ),
    );
  }
}
