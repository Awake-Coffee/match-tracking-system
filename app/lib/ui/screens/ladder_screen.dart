import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../ladder/ladder_view.dart';
import '../widgets/load_view.dart';

class LadderScreen extends StatelessWidget {
  const LadderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final meId = context.repo.me?.id;
    return LoadView(
      load: (repo) => repo.ladder(),
      builder: (context, players, _) {
        if (players.isEmpty) {
          return MessageView(
            message: 'No one is on the ladder yet.',
            actionLabel: 'Record the first game',
            onAction: () => context.go('/record'),
          );
        }
        return ListView(
          children: [
            LadderView(
              data: LadderData(
                players: players,
                meId: meId,
                now: DateTime.now(),
                onOpen: (p) => p.id == meId ? context.go('/me') : context.push('/players/${p.id}'),
              ),
            ),
          ],
        );
      },
    );
  }
}
