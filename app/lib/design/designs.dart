import 'package:flutter/material.dart';

import 'design_spec.dart';

// The five designs. Rationale and palettes are documented in
// specs/001-chess-elo-tracking/design.md; WCAG contrast is enforced by
// test/design_contrast_test.dart.

const chalkboard = DesignSpec(
  id: 'chalkboard',
  name: 'Chalkboard',
  tagline: 'Written on the specials board, under today\'s cake.',
  brightness: Brightness.dark,
  background: Color(0xFF26302B),
  surface: Color(0xFF303C36),
  ink: Color(0xFFECEAE3),
  muted: Color(0xFFA7B0A9),
  accent: Color(0xFFF1D27A),
  onAccent: Color(0xFF26302B),
  win: Color(0xFFA9D6A1),
  loss: Color(0xFFEBA9A2),
  line: Color(0xFF7D8A83),
  highlight: Color(0xFF3B4842),
  displayFamily: 'Cabin Sketch',
  bodyFamily: 'Cabin',
  displayWeight: FontWeight.w700,
  ladderStyle: LadderStyle.menu,
  radius: 4,
  lineWidth: 1.5,
  dashed: true,
);

const receipt = DesignSpec(
  id: 'receipt',
  name: 'Receipt',
  tagline: 'Every game is an order off the ticket printer.',
  brightness: Brightness.light,
  background: Color(0xFFDCDDD8),
  surface: Color(0xFFFBFBF7),
  ink: Color(0xFF232323),
  muted: Color(0xFF575752),
  accent: Color(0xFFB42A2A),
  onAccent: Color(0xFFFBFBF7),
  win: Color(0xFF2E5E8C),
  loss: Color(0xFFB42A2A),
  line: Color(0xFF8E8E87),
  highlight: Color(0xFFEDEDE6),
  displayFamily: 'Courier Prime',
  bodyFamily: 'Courier Prime',
  displayWeight: FontWeight.w700,
  ladderStyle: LadderStyle.receipt,
  radius: 0,
  dashed: true,
  tornEdge: true,
);

const crema = DesignSpec(
  id: 'crema',
  name: 'Crema',
  tagline: 'The top three, seen from above the cup.',
  brightness: Brightness.dark,
  background: Color(0xFF24170F),
  surface: Color(0xFF33231A),
  ink: Color(0xFFF2E7D8),
  muted: Color(0xFFB39C86),
  accent: Color(0xFFD9A35F),
  onAccent: Color(0xFF24170F),
  win: Color(0xFF9CC49A),
  loss: Color(0xFFE79A97),
  line: Color(0xFF5A4334),
  highlight: Color(0xFF43301F),
  displayFamily: 'Young Serif',
  bodyFamily: 'Instrument Sans',
  ladderStyle: LadderStyle.cups,
  radius: 20,
);

const bauhaus = DesignSpec(
  id: 'bauhaus',
  name: 'Bauhaus',
  tagline: 'After Hartwig\'s 1923 chess set: circle, square, triangle.',
  brightness: Brightness.light,
  background: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  ink: Color(0xFF000000),
  muted: Color(0xFF5E5E5E),
  accent: Color(0xFFD7372B),
  onAccent: Color(0xFFFFFFFF),
  win: Color(0xFF1F4FA3),
  loss: Color(0xFFD7372B),
  line: Color(0xFF000000),
  highlight: Color(0xFFF5C02E),
  displayFamily: 'Josefin Sans',
  bodyFamily: 'Work Sans',
  displayWeight: FontWeight.w700,
  ladderStyle: LadderStyle.bars,
  radius: 0,
  lineWidth: 3,
);

const sunrise = DesignSpec(
  id: 'sunrise',
  name: 'Sunrise',
  tagline: 'Awake, literally: first light on the morning shift.',
  brightness: Brightness.light,
  background: Color(0xFFEAF1FA),
  surface: Color(0xFFFFFFFF),
  ink: Color(0xFF1D2A4B),
  muted: Color(0xFF55617F),
  accent: Color(0xFFFFA41B),
  onAccent: Color(0xFF1D2A4B),
  win: Color(0xFF237A55),
  loss: Color(0xFFAE3A2B),
  line: Color(0xFFC9D6EA),
  highlight: Color(0xFFFFEBC7),
  displayFamily: 'Bagel Fat One',
  bodyFamily: 'Figtree',
  ladderStyle: LadderStyle.sky,
  radius: 999,
  chartColor: Color(0xFFB45F06),
);

const designs = [chalkboard, receipt, crema, bauhaus, sunrise];

DesignSpec designById(String? id) =>
    designs.firstWhere((d) => d.id == id, orElse: () => chalkboard);
