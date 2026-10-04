import 'dart:math' as math;

import 'package:awake_ladder/design/designs.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void aa(String what, Color fg, Color bg, [double min = 4.5]) {
  test('$what ≥ $min:1', () {
    expect(
      _contrast(fg, bg),
      greaterThanOrEqualTo(min),
      reason: '$what is ${_contrast(fg, bg).toStringAsFixed(2)}:1',
    );
  });
}

void main() {
  // SC-005 / SC-104 / SC-203: every design meet WCAG AA for the text they draw.
  for (final (name, d) in [
    ('Roast pawns', roastPawns),
    ('Baize', baize),
    ('Holotable', holotable),
    ('Holotable ground', holotableGround),
  ]) {
    group(name, () {
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
      aa('badge count on loss', d.onAccent, d.loss);
      aa('chart line on background', d.accent, d.background, 3);
    });
  }

  // Baize's rank chips sit on the opposite point color.
  aa('Baize rank on oxblood chip', baize.ink, baizeOxbloodPoint);
  aa('Baize rank on ivory chip', baize.surface, baizeIvoryPoint);
  aa('Baize selected match length', baize.surface, baize.ink);
  // Gold on felt clears AA only as large text, so the chase line stays large.
  aa(
    'Baize chase line on background (large text)',
    baize.accent,
    baize.background,
    3,
  );

  // Holotable's route dots and gap labels sit on both arenas.
  aa('Holotable gap label on space', holotable.accent, holotable.background);
  aa(
    'Holotable gap label on ground',
    holotableGround.accent,
    holotableGround.background,
  );
}
