import 'package:flutter/material.dart';

import 'design_spec.dart';

// WCAG contrast is enforced by test/design_contrast_test.dart.

const roastPawns = DesignSpec(
  brightness: Brightness.dark,
  background: Color(0xFF2A1810),
  surface: Color(0xFF3E2619),
  ink: Color(0xFFF7EEE1),
  muted: Color(0xFFBFA58A),
  accent: Color(0xFFD69A52),
  onAccent: Color(0xFF2A1810),
  win: Color(0xFFA8CF9B),
  loss: Color(0xFFE9A196),
  line: Color(0xFF6B4A33),
  highlight: Color(0xFF4A2E1E),
  displayFamily: 'Gloock',
  bodyFamily: 'Karla',
  radius: 2,
);

/// Baize, the backgammon design: a felt table where the ladder is a race
/// of board points.
const baize = DesignSpec(
  brightness: Brightness.dark,
  background: Color(0xFF1F5C46),
  surface: Color(0xFF163F31),
  ink: Color(0xFFF3EEDD),
  muted: Color(0xFFB9CBB8),
  accent: Color(0xFFD4AF4A),
  onAccent: Color(0xFF163F31),
  win: Color(0xFFD9E8A6),
  loss: Color(0xFFF2B8AE),
  line: Color(0xFF3E7A62),
  highlight: Color(0xFF2A6E55),
  displayFamily: 'Big Shoulders Display',
  bodyFamily: 'Work Sans',
  displayWeight: FontWeight.w800,
  radius: 6,
);

/// The two colors of Baize's board points, alternating down the ladder.
const baizeIvoryPoint = Color(0xFFEDE3C8);
const baizeOxbloodPoint = Color(0xFF8C2A2A);

/// Holotable, the Star Wars: Unlimited design: a briefing-room projection
/// where the ladder is a route and rating gaps are distances on it.
const holotable = DesignSpec(
  brightness: Brightness.dark,
  background: Color(0xFF0E2129),
  surface: Color(0xFF15303A),
  ink: Color(0xFFE4FAFD),
  muted: Color(0xFF8FB9C2),
  accent: Color(0xFF7FE6F2),
  onAccent: Color(0xFF0B2027),
  win: Color(0xFF9DF2B5),
  loss: Color(0xFFFFB59E),
  line: Color(0xFF2F6774),
  highlight: Color(0xFF1B4350),
  displayFamily: 'Chakra Petch',
  bodyFamily: 'Chakra Petch',
  displayWeight: FontWeight.w700,
  radius: 6,
);

/// Holotable's ground arena: players below the starting rating, and the
/// rating preview, sit on warm sand instead of the projection.
const holotableGround = DesignSpec(
  brightness: Brightness.dark,
  background: Color(0xFF2A2419),
  surface: Color(0xFF342C1F),
  ink: Color(0xFFF3EBDA),
  muted: Color(0xFFCDB894),
  accent: Color(0xFFE8C27A),
  onAccent: Color(0xFF2A2419),
  win: Color(0xFF9DF2B5),
  loss: Color(0xFFFFB59E),
  line: Color(0xFF5A4C33),
  highlight: Color(0xFF3F3524),
  displayFamily: 'Chakra Petch',
  bodyFamily: 'Chakra Petch',
  displayWeight: FontWeight.w700,
  radius: 6,
);
