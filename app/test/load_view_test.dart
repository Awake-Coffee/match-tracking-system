import 'dart:async';

import 'package:awake_ladder/data/demo_repository.dart';
import 'package:awake_ladder/data/ladder_repository.dart';
import 'package:awake_ladder/design/design_scope.dart';
import 'package:awake_ladder/design/designs.dart';
import 'package:awake_ladder/ui/app_scope.dart';
import 'package:awake_ladder/ui/widgets/load_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: DesignScope(
    spec: baize,
    child: AppScope(
      repository: DemoLadderRepository(),
      child: Scaffold(body: child),
    ),
  ),
);

Widget _loadView(Future<String> Function(LadderRepository) load) =>
    _host(LoadView<String>(load: load, builder: (_, data, _) => Text(data)));

void main() {
  group('LoadingSkeleton', () {
    testWidgets('draws surface blocks in the design radius, no spinner', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const LoadingSkeleton()));

      final rows = find.byKey(const ValueKey('skeleton-row'));
      expect(rows, findsNWidgets(LoadingSkeleton.rows));
      final box =
          tester.widget<Container>(rows.first).decoration! as BoxDecoration;
      expect(box.color, baize.surface);
      expect(box.borderRadius, baize.borderRadius);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('is announced to screen readers as loading', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const LoadingSkeleton()));

      expect(
        tester.getSemantics(find.byType(LoadingSkeleton)),
        matchesSemantics(label: 'Loading', isLiveRegion: true),
      );
      handle.dispose();
    });
  });

  group('LoadView', () {
    testWidgets('shows the skeleton while a slow load runs, then the data', (
      tester,
    ) async {
      final gate = Completer<String>();
      await tester.pumpWidget(_loadView((_) => gate.future));

      expect(find.byType(LoadingSkeleton), findsNothing);
      await tester.pump(LoadView.skeletonDelay);
      expect(find.byType(LoadingSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      gate.complete('Loaded');
      await tester.pumpAndSettle();

      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(find.text('Loaded'), findsOneWidget);
    });

    testWidgets('a cached load never shows or announces the skeleton', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_loadView((_) => Future.value('Cached')));

      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(find.bySemanticsLabel('Loading'), findsNothing);
      await tester.pump();
      expect(find.text('Cached'), findsOneWidget);
      await tester.pump(LoadView.skeletonDelay * 2);
      expect(find.byType(LoadingSkeleton), findsNothing);
      handle.dispose();
    });

    testWidgets('a new reloadKey reloads this view, not the repository', (
      tester,
    ) async {
      final repo = DemoLadderRepository();
      final revision = repo.revision;
      Widget keyed(String key) => MaterialApp(
        home: DesignScope(
          spec: baize,
          child: AppScope(
            repository: repo,
            child: Scaffold(
              body: LoadView<String>(
                reloadKey: key,
                load: (_) async => key,
                builder: (_, data, _) => Text(data),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(keyed('a'));
      await tester.pump();
      expect(find.text('a'), findsOneWidget);

      await tester.pumpWidget(keyed('b'));
      await tester.pump();
      expect(find.text('b'), findsOneWidget);
      expect(repo.revision, revision);
    });

    testWidgets('a load overtaken by a newer one never lands', (tester) async {
      final gates = {
        'first': Completer<String>()..complete('first'),
        'stale': Completer<String>(),
        'newest': Completer<String>(),
      };
      Widget keyed(String key) => _host(
        LoadView<String>(
          reloadKey: key,
          load: (_) => gates[key]!.future,
          builder: (_, data, _) => Text(data),
        ),
      );
      await tester.pumpWidget(keyed('first'));
      await tester.pump();
      await tester.pumpWidget(keyed('stale'));
      await tester.pumpWidget(keyed('newest'));

      // The newest load lands first, the overtaken one after it.
      gates['newest']!.complete('newest');
      await tester.pump();
      gates['stale']!.complete('stale');
      await tester.pump();
      // Any later rebuild must still show the newest.
      await tester.pumpWidget(keyed('newest'));
      await tester.pump();

      expect(find.text('newest'), findsOneWidget);
      expect(find.text('stale'), findsNothing);
    });
  });
}
