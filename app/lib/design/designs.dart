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
