import 'package:flutter/material.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../app_scope.dart';

/// Runs [load] and shows its result, re-running whenever ratings or matches
/// change (the repository's revision moves).
class LoadView<T> extends StatefulWidget {
  const LoadView({super.key, required this.load, required this.builder});

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = context.repo;
    if (_future == null || _revision != repo.revision) {
      _revision = repo.revision;
      _future = widget.load(repo);
    }
  }

  Future<void> _reload() async {
    final future = widget.load(context.repo);
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return MessageView(
            message: snap.error is LadderException
                ? snap.error.toString()
                : 'Couldn\'t load this. Check your connection and try again.',
            actionLabel: 'Try again',
            onAction: _reload,
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: widget.builder(context, snap.data as T, _reload),
        );
      },
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
