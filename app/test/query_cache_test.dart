import 'dart:async';

import 'package:awake_ladder/data/query_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QueryCache', () {
    test('two loads with the same key hit the backend once', () async {
      final cache = QueryCache();
      var hits = 0;
      Future<List<int>> fetch() async => [++hits];

      final first = await cache.of(('matches', 'chess', null, 50), fetch);
      final second = await cache.of(('matches', 'chess', null, 50), fetch);

      expect(hits, 1);
      expect(second, same(first));
    });

    test('a load in flight is shared, not started again', () async {
      final cache = QueryCache();
      final gate = Completer<int>();
      var hits = 0;
      Future<int> fetch() {
        hits++;
        return gate.future;
      }

      final a = cache.of('k', fetch);
      final b = cache.of('k', fetch);
      gate.complete(7);

      expect(await a, 7);
      expect(await b, 7);
      expect(hits, 1);
    });

    test('different parameters are fetched separately', () async {
      final cache = QueryCache();
      var hits = 0;
      Future<int> fetch() async => ++hits;

      await cache.of(('matches', 'chess', null, 50), fetch);
      await cache.of(('matches', 'backgammon', null, 50), fetch);
      await cache.of(('matches', 'chess', 'ana', 50), fetch);
      await cache.of(('matches', 'chess', 'ana', 500), fetch);
      await cache.of(('match_requests', 'chess', null, null), fetch);

      expect(hits, 5);
    });

    test('clearing refetches, as when the data changes', () async {
      final cache = QueryCache();
      var hits = 0;
      Future<int> fetch() async => ++hits;

      expect(await cache.of('k', fetch), 1);
      cache.clear();
      expect(await cache.of('k', fetch), 2);
    });

    test('a failed fetch is dropped so the next load retries', () async {
      final cache = QueryCache();
      var hits = 0;
      Future<int> fetch() async {
        if (++hits == 1) throw Exception('offline');
        return hits;
      }

      await expectLater(cache.of('k', fetch), throwsException);
      expect(await cache.of('k', fetch), 2);
      expect(hits, 2);
    });

    test('a failure that lands after a clear keeps the newer fetch', () async {
      final cache = QueryCache();
      final slow = Completer<int>();
      final stale = cache.of('k', () => slow.future);
      final stalled = expectLater(stale, throwsException);

      cache.clear();
      var hits = 0;
      Future<int> fresh() async => ++hits;
      expect(await cache.of('k', fresh), 1);

      slow.completeError(Exception('late'));
      await stalled;
      expect(await cache.of('k', fresh), 1);
      expect(hits, 1);
    });
  });
}
