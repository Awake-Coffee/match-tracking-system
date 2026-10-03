import 'dart:math' as math;

import 'package:awake_ladder/design/designs.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  // SC-005: the design meets WCAG AA for the text it draws.
  const d = roastPawns;
  void aa(String what, Color fg, Color bg, [double min = 4.5]) {
    test('$what ≥ $min:1', () {
      expect(
        _contrast(fg, bg),
        greaterThanOrEqualTo(min),
        reason: '$what is ${_contrast(fg, bg).toStringAsFixed(2)}:1',
      );
    });
  }

  aa('ink on background', d.ink, d.background);
  aa('ink on surface', d.ink, d.surface);
  aa('ink on highlight', d.ink, d.highlight);
  aa('muted on background', d.muted, d.background);
  aa('muted on surface', d.muted, d.surface);
  aa('button label on accent', d.onAccent, d.accent);
  aa('win text on surface', d.win, d.surface);
  aa('loss text on surface', d.loss, d.surface);
  aa('win text on background', d.win, d.background);
  aa('loss text on background', d.loss, d.background);
  aa('chart line on background', d.accent, d.background, 3);
}
