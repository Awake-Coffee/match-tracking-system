import 'package:flutter/widgets.dart';

import 'design_spec.dart';

/// Makes the active [DesignSpec] available below it.
class DesignScope extends InheritedWidget {
  const DesignScope({super.key, required this.spec, required super.child});

  final DesignSpec spec;

  static DesignSpec of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesignScope>()!.spec;

  @override
  bool updateShouldNotify(DesignScope oldWidget) => spec != oldWidget.spec;
}

extension DesignContext on BuildContext {
  DesignSpec get design => DesignScope.of(this);
}
