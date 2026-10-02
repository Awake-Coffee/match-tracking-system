import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/load_view.dart';
import '../widgets/match_tile.dart';
import '../widgets/surface.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LoadView(
      load: (repo) => repo.matches(limit: 100),
      builder: (context, matches, _) => ListView(
        children: [
          const ScreenTitle('History', subtitle: 'Every game at the café, newest first.'),
          if (matches.isEmpty)
            MessageView(
              message: 'No games yet.',
              actionLabel: 'Record the first game',
              onAction: () => context.go('/record'),
            ),
          for (final (i, m) in matches.indexed) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: SpecRule(verticalPadding: 0),
              ),
            MatchTile(match: m),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
