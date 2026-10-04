import 'package:awake_ladder/data/live_updates.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [LiveUpdates] with a fake push channel, counting catch-ups.
class _Harness {
  _Harness() {
    live = LiveUpdates(
      onChanged: () => changes++,
      subscribe: (onEvent) {
        subscriptions++;
        push = onEvent;
        return () => unsubscriptions++;
      },
    );
  }

  late final LiveUpdates live;
  late VoidCallback push;
  int changes = 0;
  int subscriptions = 0;
  int unsubscriptions = 0;
}

void _lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

// Each test stops what it started: the binding checks for pending timers
// before tear-downs run.
void main() {
  testWidgets('events arriving together reload once', (tester) async {
    final h = _Harness()..live.start();

    h.push();
    h.push();
    await tester.pump(const Duration(milliseconds: 100));
    h.push();
    expect(h.changes, 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.changes, 1);
    h.live.stop();
  });

  testWidgets('starting twice subscribes once', (tester) async {
    final h = _Harness()
      ..live.start()
      ..live.start();
    expect(h.subscriptions, 1);
    h.live.stop();
  });

  testWidgets('polls only while the app is visible', (tester) async {
    final h = _Harness()..live.start();

    await tester.pump(const Duration(seconds: 60));
    expect(h.changes, 1);

    _lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.hidden]);
    await tester.pump(const Duration(seconds: 120));
    expect(h.changes, 1);

    // Coming back catches up at once, then polling resumes.
    _lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.resumed]);
    expect(h.changes, 2);
    await tester.pump(const Duration(seconds: 60));
    expect(h.changes, 3);
    h.live.stop();
  });

  testWidgets('stopping tears everything down', (tester) async {
    final h = _Harness()..live.start();
    h.push();
    h.live.stop();
    h.live.stop();
    expect(h.unsubscriptions, 1);

    h.push();
    await tester.pump(const Duration(seconds: 120));
    _lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.resumed]);
    expect(h.changes, 0);
    expect(h.live.isLive, isFalse);
  });
}
