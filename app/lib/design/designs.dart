import 'package:flutter/material.dart';

import 'design_spec.dart';

// WCAG contrast is enforced by test/design_contrast_test.dart.

/// Counter, the chess design: the café's letterboard. White capitals on
/// ridged black felt, ratings at the end of dotted leaders like prices on a
/// menu. There is no accent color: emphasis is the board inverted, ink
/// behind background-colored letters. Follows the system's light or dark
/// setting; [counterLight] is the same board in white felt.
const counterDark = DesignSpec(
  brightness: Brightness.dark,
  background: Color(0xFF161514),
  surface: Color(0xFF201E1B),
  ink: Color(0xFFF2EDE4),
  muted: Color(0xFFA9A196),
  accent: Color(0xFFF2EDE4),
  onAccent: Color(0xFF161514),
  win: Color(0xFF9BD3A0),
  loss: Color(0xFFF0A08C),
  line: Color(0xFF4A463F),
  highlight: Color(0xFF2B2925),
  displayFamily: 'Archivo Narrow',
  bodyFamily: 'Archivo',
  displayWeight: FontWeight.w700,
  displayTracking: 0.06,
  allCaps: true,
  grain: Color(0x09FFFFFF),
  textTabs: true,
  labelsInDisplayFace: true,
  leaders: true,
  radius: 0,
);

/// Counter on white felt, for the system's light setting.
const counterLight = DesignSpec(
  brightness: Brightness.light,
  background: Color(0xFFECE8E0),
  surface: Color(0xFFE2DDD3),
  ink: Color(0xFF1A1814),
  muted: Color(0xFF5E584F),
  accent: Color(0xFF1A1814),
  onAccent: Color(0xFFECE8E0),
  win: Color(0xFF2E6B3A),
  loss: Color(0xFF9E3219),
  line: Color(0xFFC4BDB0),
  highlight: Color(0xFFDCD6CB),
  displayFamily: 'Archivo Narrow',
  bodyFamily: 'Archivo',
  displayWeight: FontWeight.w700,
  displayTracking: 0.06,
  allCaps: true,
  grain: Color(0x0D1A1814),
  textTabs: true,
  labelsInDisplayFace: true,
  leaders: true,
  radius: 0,
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
  // Gold on felt is AA only as large text.
  chaseDisplaySize: 26,
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
