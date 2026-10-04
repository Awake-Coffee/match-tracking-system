import 'package:flutter/material.dart';

import '../../design/design_scope.dart';

/// A raised panel in the design's shape language.
class SpecSurface extends StatelessWidget {
  const SpecSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.outlined = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? d.surface,
        borderRadius: d.borderRadius,
        border: outlined ? Border.all(color: d.line, width: d.lineWidth) : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// The design's background behind [child], ridged with its grain if it has
/// one.
class SpecBackdrop extends StatelessWidget {
  const SpecBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final grain = d.grain;
    if (grain == null) return ColoredBox(color: d.background, child: child);
    return CustomPaint(
      painter: _GrainPainter(background: d.background, grain: grain),
      child: child,
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter({required this.background, required this.grain});

  final Color background;
  final Color grain;

  /// Distance between ridges, as on letterboard felt.
  static const _pitch = 9.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final ridge = Paint()..color = grain;
    for (var y = 0.0; y < size.height; y += _pitch) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), ridge);
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) =>
      old.background != background || old.grain != grain;
}

/// [lead] followed by a dotted leader running to the end of the space it is
/// given, like a menu's dish and the dots to its price. [lead] keeps its own
/// width, up to all but [minLeader] of the space, and ellipsizes past that.
/// Lay it out in an Expanded with the number after it, so every leader in a
/// list ends at the same edge.
class LeaderRow extends StatelessWidget {
  const LeaderRow({
    super.key,
    required this.lead,
    required this.color,
    this.baselineGap = 6,
    this.minLeader = 24,
  });

  final Widget lead;
  final Color color;

  /// Lifts the dots off the bottom edge to sit on the text's baseline.
  final double baselineGap;
  final double minLeader;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (constraints.maxWidth - minLeader).clamp(
              0,
              double.infinity,
            ),
          ),
          child: lead,
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, baselineGap),
            child: DottedLeader(color: color),
          ),
        ),
      ],
    ),
  );
}

/// A dotted leader filling the space between a name and its number, like a
/// menu's line between a dish and its price.
class DottedLeader extends StatelessWidget {
  const DottedLeader({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 2,
    width: double.infinity,
    child: CustomPaint(painter: _DotsPainter(color)),
  );
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = color;
    for (var x = 0.0; x + 2 <= size.width; x += 5) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), dot);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}

/// A horizontal rule in the design's line style.
class SpecRule extends StatelessWidget {
  const SpecRule({super.key, this.verticalPadding = 12});

  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Divider(
        height: d.lineWidth,
        thickness: d.lineWidth,
        color: d.line,
      ),
    );
  }
}

/// Signed rating change, e.g. "+16", "−8", "±0".
String formatDelta(int delta) => delta > 0
    ? '+$delta'
    : delta < 0
    ? '−${-delta}'
    : '±0';

class DeltaText extends StatelessWidget {
  const DeltaText(this.delta, {super.key, this.size = 14});

  final int delta;
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Text(
      formatDelta(delta),
      style: d.number(
        size,
        color: d.outcomeColor(delta),
        weight: FontWeight.w700,
      ),
    );
  }
}

/// Title row used at the top of screens.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key, this.trailing, this.subtitle});

  final String text;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.caps(text), style: d.display(34)),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(subtitle!, style: d.body(15, color: d.muted)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
