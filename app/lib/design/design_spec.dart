import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// How a design draws the ladder: the one place each design is bold.
enum LadderStyle { menu, receipt, cups, bars, sky }

/// Tests turn this off so fonts aren't fetched from the network.
bool useGoogleFonts = true;

/// The full set of tokens a design provides. Screens read these instead of
/// hardcoding colors, type or shapes (constitution principle V).
@immutable
class DesignSpec {
  const DesignSpec({
    required this.id,
    required this.name,
    required this.tagline,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.win,
    required this.loss,
    required this.line,
    required this.highlight,
    required this.displayFamily,
    required this.bodyFamily,
    required this.ladderStyle,
    this.displayWeight = FontWeight.w400,
    this.radius = 8,
    this.lineWidth = 1,
    this.dashed = false,
    this.tornEdge = false,
    this.chartColor,
  });

  /// Stored on the profile (`profiles.design`).
  final String id;
  final String name;

  /// One sentence shown in the design picker.
  final String tagline;
  final Brightness brightness;

  final Color background;
  final Color surface;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color win;
  final Color loss;
  final Color line;

  /// Background for "this is you" rows.
  final Color highlight;

  final String displayFamily;
  final String bodyFamily;
  final FontWeight displayWeight;
  final LadderStyle ladderStyle;

  /// Corner radius for surfaces; 999 means pill-shaped.
  final double radius;
  final double lineWidth;
  final bool dashed;

  /// Receipt slips have a zigzag bottom edge.
  final bool tornEdge;

  /// Line color for charts when [accent] lacks 3:1 contrast on [background].
  final Color? chartColor;

  Color get chart => chartColor ?? accent;

  bool get pill => radius >= 999;

  TextStyle display(double size, {Color? color, FontWeight? weight, double? height}) =>
      _font(displayFamily, TextStyle(
        fontSize: size,
        fontWeight: weight ?? displayWeight,
        color: color ?? ink,
        height: height ?? 1.1,
      ));

  TextStyle body(double size, {Color? color, FontWeight? weight, double? height}) =>
      _font(bodyFamily, TextStyle(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        color: color ?? ink,
        height: height ?? 1.4,
      ));

  /// Tabular figures so ratings line up in columns.
  TextStyle number(double size, {Color? color, FontWeight? weight, bool displayFace = false}) =>
      (displayFace ? display(size, color: color, weight: weight) : body(size, color: color, weight: weight))
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle _font(String family, TextStyle style) {
    if (!useGoogleFonts) return style.copyWith(fontFamily: family);
    return GoogleFonts.getFont(family, textStyle: style);
  }

  Color outcomeColor(int delta) =>
      delta > 0 ? win : delta < 0 ? loss : muted;

  BorderRadius get borderRadius => BorderRadius.circular(pill ? 28 : radius);

  OutlinedBorder buttonShape() => pill
      ? const StadiumBorder()
      : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

  ThemeData toTheme() {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: win,
      onSecondary: background,
      error: loss,
      onError: brightness == Brightness.dark ? background : Colors.white,
      surface: background,
      onSurface: ink,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surface,
      surfaceContainerHighest: surface,
      onSurfaceVariant: muted,
      outline: line,
      outlineVariant: line.withValues(alpha: 0.5),
      secondaryContainer: highlight,
      onSecondaryContainer: ink,
    );

    final textTheme = TextTheme(
      bodyLarge: body(16),
      bodyMedium: body(14),
      bodySmall: body(12, color: muted),
      labelLarge: body(15, weight: FontWeight.w600),
      labelMedium: body(13, weight: FontWeight.w600),
      labelSmall: body(11, weight: FontWeight.w600),
      titleLarge: display(22),
      titleMedium: body(16, weight: FontWeight.w600),
      titleSmall: body(14, weight: FontWeight.w600),
      headlineLarge: display(34),
      headlineMedium: display(28),
      headlineSmall: display(24),
      displayLarge: display(56),
      displayMedium: display(44),
      displaySmall: display(36),
    );

    final side = BorderSide(color: line, width: lineWidth);
    final inputRadius = BorderRadius.circular(pill ? 28 : radius);
    final focusRing = BorderSide(color: accent, width: lineWidth + 1.5);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      dividerTheme: DividerThemeData(color: line, thickness: lineWidth, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: display(26),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: line.withValues(alpha: 0.4),
          disabledForegroundColor: muted,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: buttonShape(),
          textStyle: body(16, weight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: side,
          minimumSize: const Size(64, 48),
          shape: buttonShape(),
          textStyle: body(15, weight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          shape: buttonShape(),
          textStyle: body(15, weight: FontWeight.w600),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(buttonShape()),
          side: WidgetStatePropertyAll(side),
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          textStyle: WidgetStatePropertyAll(body(15, weight: FontWeight.w600)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? onAccent : ink,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: body(15, color: muted),
        floatingLabelStyle: body(14, color: ink, weight: FontWeight.w600),
        hintStyle: body(15, color: muted),
        helperStyle: body(13, color: muted),
        errorStyle: body(13, color: loss),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: inputRadius, borderSide: side),
        enabledBorder: OutlineInputBorder(borderRadius: inputRadius, borderSide: side),
        focusedBorder: OutlineInputBorder(borderRadius: inputRadius, borderSide: focusRing),
        errorBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: loss, width: lineWidth),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: loss, width: lineWidth + 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent,
        indicatorShape: buttonShape(),
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => body(12,
              weight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? ink : muted),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? onAccent : muted,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: body(15, color: background),
        actionTextColor: accent,
        behavior: SnackBarBehavior.floating,
        shape: buttonShape(),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: body(16),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(pill ? 20 : radius)),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      focusColor: accent.withValues(alpha: 0.25),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: ink,
        selectionColor: accent.withValues(alpha: 0.35),
      ),
    );
  }
}
