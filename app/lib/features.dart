import 'package:flutter/widgets.dart';

import 'domain/models.dart';

/// Features built but not yet shown to members. A build switches one on
/// with `--dart-define`, e.g. `--dart-define=GAME_MODES=true`. They hide
/// the UI only: data and routes stay as they are.
@immutable
class Features {
  const Features({this.gameModes = false});

  /// The features this build was given.
  static const fromEnvironment = Features(
    gameModes: bool.fromEnvironment('GAME_MODES'),
  );

  /// What the app shows when not told otherwise: [fromEnvironment]. Only
  /// tests change it (test/flutter_test_config.dart).
  static Features defaults = fromEnvironment;

  /// Chess variants beyond standard chess, each with its own ladder.
  /// Off: chess's Ladder tab opens the standard ladder, titled "Ladder", and
  /// no chess screen offers or names a mode. Backgammon and Star Wars:
  /// Unlimited show their modes either way.
  final bool gameModes;

  /// Whether screens of [type] offer and name its modes.
  bool showsModesOf(MatchType type) => gameModes || type != MatchType.chess;
}

/// Provides the build's [Features] to the screens below it.
class FeatureScope extends InheritedWidget {
  const FeatureScope({super.key, required this.features, required super.child});

  final Features features;

  static Features of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeatureScope>()?.features ??
      Features.defaults;

  @override
  bool updateShouldNotify(FeatureScope old) =>
      features.gameModes != old.features.gameModes;
}

extension FeaturesContext on BuildContext {
  Features get features => FeatureScope.of(this);
}
