import 'dart:async';

import 'package:flutter/widgets.dart';

/// Keeps a signed-in member's screens current with what other members do.
///
/// [subscribe] hears of changes the moment they happen (Supabase Realtime).
/// A push channel can silently die and misses everything while the app is
/// away, so this also catches up when the app returns to the foreground and
/// polls while it is visible. Every catch-up calls [onChanged]. Kept apart
/// from the repository so the policy is testable without a backend.
class LiveUpdates with WidgetsBindingObserver {
  LiveUpdates({
    required this.onChanged,
    required this.subscribe,
    this.pollEvery = const Duration(seconds: 60),
    this.burst = const Duration(milliseconds: 300),
  });

  final VoidCallback onChanged;

  /// Starts listening for changes, calling its argument on each one, and
  /// returns how to stop.
  final VoidCallback Function(VoidCallback onEvent) subscribe;

  /// Fallback for when the push channel is down.
  final Duration pollEvery;

  /// Events arriving together (a confirmation inserts a result and deletes
  /// its request) call [onChanged] once.
  final Duration burst;

  VoidCallback? _unsubscribe;
  Timer? _poll;
  Timer? _burst;
  bool _visible = true;

  bool get isLive => _unsubscribe != null;

  /// Safe to call repeatedly.
  void start() {
    if (isLive) return;
    final binding = WidgetsBinding.instance..addObserver(this);
    _visible = _isVisible(binding.lifecycleState ?? AppLifecycleState.resumed);
    _unsubscribe = subscribe(_onEvent);
    _poll = Timer.periodic(pollEvery, (_) {
      if (_visible) onChanged();
    });
  }

  /// Signed out or shutting down. Safe to call repeatedly.
  void stop() {
    final unsubscribe = _unsubscribe;
    if (unsubscribe == null) return;
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _burst?.cancel();
    _poll = _burst = null;
    _unsubscribe = null;
    unsubscribe();
  }

  void _onEvent() {
    // A late event from a channel being torn down.
    if (!isLive) return;
    _burst?.cancel();
    _burst = Timer(burst, onChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = _isVisible(state);
    // Events missed while away are gone, so catch up on return.
    if (state == AppLifecycleState.resumed) onChanged();
  }

  static bool _isVisible(AppLifecycleState state) => switch (state) {
    AppLifecycleState.resumed || AppLifecycleState.inactive => true,
    _ => false,
  };
}
