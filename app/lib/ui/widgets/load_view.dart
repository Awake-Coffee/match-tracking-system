import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../app_scope.dart';

/// Runs [load] and shows its result, re-running whenever ratings or matches
/// change (the repository's revision moves).
///
/// Reloads also happen in the background (other members' changes, the app
/// returning to the foreground, a poll), so a failed reload keeps what is on
/// screen, including any half-filled form, rather than replacing it with an
/// error. The error view is only for a first load that fails.
///
/// A first load that takes longer than [skeletonDelay] shows a
/// [LoadingSkeleton]; a quicker one (a warm cache on a tab switch) shows
/// nothing until it lands, so it neither flashes nor announces "Loading".
class LoadView<T> extends StatefulWidget {
  const LoadView({super.key, required this.load, required this.builder});

  static const skeletonDelay = Duration(milliseconds: 150);

  final Future<T> Function(LadderRepository repo) load;
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() reload,
  )
  builder;

  @override
  State<LoadView<T>> createState() => _LoadViewState<T>();
}

class _LoadViewState<T> extends State<LoadView<T>> {
  Future<T>? _future;
  int? _revision;

  /// The last data that loaded; a record so a null [T] still counts.
  (T,)? _last;

  /// Set once the pending load has outlasted [LoadView.skeletonDelay].
  bool _slow = false;
  Timer? _slowTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = context.repo;
    if (_future == null || _revision != repo.revision) _load(repo);
  }

  void _load(LadderRepository repo) {
    _revision = repo.revision;
    final future = _future = widget.load(repo).then((data) {
      _last = (data,);
      return data;
    });
    _slowTimer?.cancel();
    _slow = false;
    // Only a first load can show the skeleton; reloads keep the old data.
    if (_last != null) return;
    final timer = _slowTimer = Timer(LoadView.skeletonDelay, () {
      if (mounted) setState(() => _slow = true);
    });
    // Errors are shown by the FutureBuilder; this branch only stops the timer.
    future.then<void>((_) {}, onError: (_) {}).whenComplete(timer.cancel);
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  /// Pull-to-refresh and retry. Goes through the repository so the shell's
  /// badges refetch too, and loads this view right away so the spinner
  /// waits for it.
  Future<void> _reload() async {
    final repo = context.repo..reload();
    setState(() => _load(repo));
    try {
      await _future;
    } catch (_) {
      // With nothing on screen the error view says so; otherwise a quiet note.
      if (_last != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t refresh. Check your connection.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        final last = _last;
        if (last == null && snap.hasError) {
          return MessageView(
            message: snap.error is LadderException
                ? snap.error.toString()
                : 'Couldn\'t load this. Check your connection and try again.',
            actionLabel: 'Try again',
            onAction: _reload,
          );
        }
        if (last == null) {
          return _slow ? const LoadingSkeleton() : const SizedBox.expand();
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: widget.builder(context, last.$1, _reload),
        );
      },
    );
  }
}

/// What a first load shows: a few rows of blocks in the design's surface
/// colour and radius, so the page holds its shape instead of flashing a
/// spinner. Still (no shimmer) and announced as loading to screen readers.
class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key});

  static const rows = 5;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading',
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            for (var i = 0; i < rows; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  key: const ValueKey('skeleton-row'),
                  height: 64,
                  decoration: BoxDecoration(
                    color: d.surface,
                    borderRadius: d.borderRadius,
                    border: Border.all(color: d.line, width: d.lineWidth),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Centered message with an optional action: used for errors and empty states.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: d.body(16, color: d.muted),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
