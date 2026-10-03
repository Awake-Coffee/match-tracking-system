import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/ladder_repository.dart';
import 'design/design_scope.dart';
import 'design/designs.dart';
import 'ui/app_scope.dart';
import 'ui/screens/history_screen.dart';
import 'ui/screens/ladder_screen.dart';
import 'ui/screens/profile_screen.dart';
import 'ui/screens/record_screen.dart';
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
  final _theme = roastPawns.toTheme();

  LadderRepository get _repo => widget.repository;

  GoRouter _buildRouter() => GoRouter(
    initialLocation: widget.initialLocation,
    refreshListenable: _repo,
    redirect: (context, state) {
      final onSignIn = state.matchedLocation == '/sign-in';
      if (!_repo.isSignedIn) return onSignIn ? null : '/sign-in';
      if (onSignIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/sign-in',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: SignInScreen()),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: LadderScreen()),
          ),
          GoRoute(
            path: '/record',
            pageBuilder: (context, state) => NoTransitionPage(
              child: RecordScreen(
                initialOpponentId: state.uri.queryParameters['opponent'],
              ),
            ),
          ),
          GoRoute(
            path: '/history',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HistoryScreen()),
          ),
          GoRoute(
            path: '/me',
            pageBuilder: (context, state) => NoTransitionPage(
              child: ProfileScreen(playerId: _repo.me!.id, isMe: true),
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/players/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return ProfileScreen(
                key: ValueKey(id),
                playerId: id,
                isMe: id == _repo.me?.id,
              );
            },
          ),
        ],
      ),
    ],
  );

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
        spec: roastPawns,
        child: MaterialApp.router(
          title: 'Awake Chess Ladder',
          debugShowCheckedModeBanner: false,
          theme: _theme,
          routerConfig: _router,
        ),
      ),
    );
  }
}
