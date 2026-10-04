import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../game.dart';
import '../widgets/load_view.dart';

/// An address the app has no page for: a mistyped or outdated link.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, required this.game});

  /// The game whose address this looked like, whose ladder it leads to.
  final Game game;

  @override
  Widget build(BuildContext context) {
    return MessageView(
      message: 'There\'s no page at this address.',
      actionLabel: 'Go to the ladder',
      onAction: () => context.go(game.path()),
    );
  }
}
