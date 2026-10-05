import 'dart:async';

import 'package:awake_ladder/features.dart';

/// Runs before every test file. The suite covers every feature built,
/// including those a release still hides, so they're switched on here;
/// test/features_test.dart covers the app as released, with them off.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Features.defaults = const Features(gameModes: true);
  await testMain();
}
