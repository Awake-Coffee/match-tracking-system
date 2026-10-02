import 'package:flutter/material.dart';

import '../../design/design_scope.dart';

/// A raised panel drawn in the active design's shape language: solid or
/// dashed outline, rounded or square, and a torn zigzag edge for receipts.
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
    final fill = color ?? d.surface;
    final radius = d.pill ? 28.0 : d.radius;

    if (d.tornEdge) {
      return CustomPaint(
        painter: _TornPaperPainter(fill: fill),
        child: Padding(
          padding: padding.add(const EdgeInsets.only(bottom: _TornPaperPainter.tooth)),
          child: child,
        ),
      );
    }

    if (d.dashed && outlined) {
      return CustomPaint(
        painter: _DashedBorderPainter(
          color: d.line,
          width: d.lineWidth,
          radius: radius,
          fill: fill,
        ),
        child: Padding(padding: padding, child: child),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: outlined ? Border.all(color: d.line, width: d.lineWidth) : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
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
      child: SizedBox(
        height: d.lineWidth,
        width: double.infinity,
        child: CustomPaint(
          painter: _RulePainter(color: d.line, width: d.lineWidth, dashed: d.dashed),
        ),
      ),
    );
  }
}

class _RulePainter extends CustomPainter {
  _RulePainter({required this.color, required this.width, required this.dashed});

  final Color color;
  final double width;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    for (double x = 0; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, y), Offset((x + 5).clamp(0, size.width), y), paint);
    }
  }

  @override
  bool shouldRepaint(_RulePainter old) =>
      old.color != color || old.width != width || old.dashed != dashed;
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    required this.width,
    required this.radius,
    required this.fill,
  });

  final Color color;
  final double width;
  final double radius;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(width / 2), Radius.circular(radius));
    canvas.drawRRect(rrect, Paint()..color = fill);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 6), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.fill != fill || old.radius != radius || old.width != width;
}

class _TornPaperPainter extends CustomPainter {
  _TornPaperPainter({required this.fill});

  static const tooth = 8.0;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, bottom - tooth);
    final teeth = (size.width / (tooth * 2)).ceil();
    final step = size.width / teeth;
    for (var i = teeth; i > 0; i--) {
      final x = i * step;
      path
        ..lineTo(x - step / 2, bottom)
        ..lineTo(x - step, bottom - tooth);
    }
    path.close();
    canvas.drawShadow(path, const Color(0x55000000), 1.5, false);
    canvas.drawPath(path, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_TornPaperPainter old) => old.fill != fill;
}

/// Signed rating change, e.g. "+16", "−8", "±0".
String formatDelta(int delta) =>
    delta > 0 ? '+$delta' : delta < 0 ? '−${-delta}' : '±0';

class DeltaText extends StatelessWidget {
  const DeltaText(this.delta, {super.key, this.size = 14});

  final int delta;
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Text(
      formatDelta(delta),
      style: d.number(size, color: d.outcomeColor(delta), weight: FontWeight.w700),
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
                Text(text, style: d.display(34)),
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
