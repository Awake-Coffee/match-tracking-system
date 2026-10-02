import 'package:flutter/widgets.dart';

import '../data/ladder_repository.dart';

/// Provides the [LadderRepository] and rebuilds dependents when it changes.
class AppScope extends InheritedNotifier<LadderRepository> {
  const AppScope({
    super.key,
    required LadderRepository repository,
    required super.child,
  }) : super(notifier: repository);

  static LadderRepository of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension RepositoryContext on BuildContext {
  LadderRepository get repo => AppScope.of(this);
}
