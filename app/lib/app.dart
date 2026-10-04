import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/ladder_repository.dart';
import 'design/design_scope.dart';
import 'ui/app_scope.dart';
import 'ui/game.dart';
import 'ui/screens/history_screen.dart';
import 'ui/screens/ladder_screen.dart';
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

class _AwakeAppState extends State<AwakeApp> {
  late final GoRouter _router = _buildRouter();
  final _themes = {for (final g in Game.values) g: g.design.toTheme()};

  LadderRepository get _repo => widget.repository;

  GoRouter _buildRouter() => GoRouter(
    initialLocation: widget.initialLocation,
    refreshListenable: _repo,
    redirect: (context, state) {
      final onSignIn = state.matchedLocation == '/sign-in';
      final onReset = state.matchedLocation == '/reset-password';
      // The recovery link signs the member in only to choose a new password.
      if (_repo.passwordRecoveryPending) {
        return onReset ? null : '/reset-password';
      }
      // Signed in without a pending recovery (a reload, or a restored tab,
      // forgets the flag): stay, since the member may not know their password.
      if (onReset) return _repo.isSignedIn ? null : '/sign-in';
      if (!_repo.isSignedIn) return onSignIn ? null : '/sign-in';
      if (onSignIn) return '/';
      return null;
    },
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
          return DesignScope(
            spec: game.design,
            child: Theme(
              data: _themes[game]!,
              child: AppShell(
                game: game,
                location: state.uri.path,
                child: child,
              ),
            ),
          );
        },
        routes: [for (final game in Game.values) ..._gameRoutes(game)],
      ),
    ],
  );

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
      path: game.path('record'),
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: RecordScreen(
          game: game,
          initialOpponentId: state.uri.queryParameters['opponent'],
        ),
      ),
    ),
    GoRoute(
      path: game.path('history'),
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: HistoryScreen(game: game),
      ),
    ),
    GoRoute(
      path: game.path('me'),
      pageBuilder: (context, state) => NoTransitionPage(
        key: state.pageKey,
        child: ProfileScreen(game: game, playerId: _repo.me!.id, isMe: true),
      ),
    ),
    GoRoute(
      path: game.path('settings'),
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: game.path('players/:id'),
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return ProfileScreen(
          key: ValueKey((game, id)),
          game: game,
          playerId: id,
          isMe: id == _repo.me?.id,
        );
      },
    ),
  ];

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      repository: _repo,
      child: DesignScope(
        spec: Game.chess.design,
        child: MaterialApp.router(
          title: 'Awake Ladder',
          debugShowCheckedModeBanner: false,
          theme: _themes[Game.chess],
          routerConfig: _router,
        ),
      ),
    );
  }
}
