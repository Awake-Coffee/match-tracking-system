import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../ladder/ladder_view.dart';
import '../ladder/pawns_ladder.dart';
import '../widgets/load_view.dart';
import '../widgets/match_request_list.dart';

class LadderScreen extends StatelessWidget {
  const LadderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final meId = context.repo.me?.id;
    return LoadView(
      load: (repo) => (repo.ladder(), repo.matchRequests()).wait,
      builder: (context, data, _) {
        final (players, requests) = data;
        if (players.isEmpty) {
          return MessageView(
            message: 'No one is on the ladder yet.',
            actionLabel: 'Record the first game',
            onAction: () => context.go('/record'),
          );
        }
        return ListView(
          children: [
            MatchRequestList(requests: requests),
            PawnsLadder(
              data: LadderData(
                players: players,
                meId: meId,
                now: DateTime.now(),
                onOpen: (p) => p.id == meId
                    ? context.go('/me')
                    : context.push('/players/${p.id}'),
              ),
            ),
          ],
        );
      },
    );
  }
}
