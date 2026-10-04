/// Memoizes in-flight and finished fetches by their parameters until
/// [clear] is called (the repository clears it whenever data changes).
///
/// Tabs remount their screens on every switch; without this each mount
/// would hit the backend again for data that has not moved.
class QueryCache {
  final _entries = <Object, Future<Object?>>{};

  /// The fetch for [key], started on first use and shared afterwards. A
  /// failure isn't kept, so the next load retries.
  Future<T> of<T>(Object key, Future<T> Function() fetch) {
    if (_entries[key] case final cached?) return cached as Future<T>;
    final future = fetch();
    _entries[key] = future;
    future.then(
      (_) {},
      onError: (Object _) {
        // Only drop our own entry: a clear may already have replaced it.
        if (identical(_entries[key], future)) _entries.remove(key);
      },
    );
    return future;
  }

  void clear() => _entries.clear();
}
