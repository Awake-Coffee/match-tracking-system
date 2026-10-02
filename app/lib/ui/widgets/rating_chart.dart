import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../../design/design_spec.dart';

/// Rating after each game as a single 2px line with a light wash, a ringed
/// end marker labelled with the current rating, and a crosshair tooltip on
/// hover or drag. Single series, so the section title names it (no legend);
/// the recent games list below is the table view.
class RatingChart extends StatefulWidget {
  const RatingChart({super.key, required this.points, required this.describe});

  /// Rating at the start and after each game, oldest first.
  final List<int> points;

  /// Tooltip text for a point index (0 is the starting rating).
  final String Function(int index) describe;

  @override
  State<RatingChart> createState() => _RatingChartState();
}

class _RatingChartState extends State<RatingChart> {
  int? _active;

  void _track(Offset local, Size size) {
    final n = widget.points.length;
    if (n < 2) return;
    final plot = _ChartGeometry.plotRect(size);
    final t = ((local.dx - plot.left) / plot.width).clamp(0.0, 1.0);
    setState(() => _active = (t * (n - 1)).round());
  }

  void _clear() => setState(() => _active = null);

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final points = widget.points;
    return Semantics(
      label: 'Rating over ${points.length - 1} games, from ${points.first} '
          'to ${points.last}, peak ${points.reduce(math.max)}',
      child: LayoutBuilder(builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 180);
        return MouseRegion(
          onHover: (e) => _track(e.localPosition, size),
          onExit: (_) => _clear(),
          child: GestureDetector(
            onPanDown: (e) => _track(e.localPosition, size),
            onPanUpdate: (e) => _track(e.localPosition, size),
            onPanEnd: (_) => _clear(),
            onPanCancel: _clear,
            child: CustomPaint(
              size: size,
              painter: _RatingPainter(
                points: points,
                design: d,
                active: _active,
                tooltip: _active == null ? null : widget.describe(_active!),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _ChartGeometry {
  static Rect plotRect(Size size) =>
      Rect.fromLTRB(44, 12, size.width - 52, size.height - 12);
}

class _RatingPainter extends CustomPainter {
  _RatingPainter({
    required this.points,
    required this.design,
    required this.active,
    required this.tooltip,
  });

  final List<int> points;
  final DesignSpec design;
  final int? active;
  final String? tooltip;

  @override
  void paint(Canvas canvas, Size size) {
    final d = design;
    final plot = _ChartGeometry.plotRect(size);
    final lo = points.reduce(math.min);
    final hi = points.reduce(math.max);

    // Clean tick step so labels read 950 / 1000 / 1050.
    final span = math.max(hi - lo, 40);
    final step = span <= 80 ? 25 : span <= 200 ? 50 : 100;
    final yMin = (lo / step).floor() * step;
    final yMax = math.max((hi / step).ceil() * step, yMin + step);

    double x(int i) => plot.left + plot.width * (points.length == 1 ? 1 : i / (points.length - 1));
    double y(num v) => plot.bottom - plot.height * (v - yMin) / (yMax - yMin);

    // Hairline, solid, recessive gridlines.
    final grid = Paint()
      ..color = d.line.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var v = yMin; v <= yMax; v += step) {
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), grid);
      _text(canvas, '$v', d.number(11, color: d.muted), Offset(plot.left - 8, y(v)), rightAlign: true);
    }

    final chart = d.chart;
    final line = Path()..moveTo(x(0), y(points[0]));
    for (var i = 1; i < points.length; i++) {
      line.lineTo(x(i), y(points[i]));
    }
    final area = Path.from(line)
      ..lineTo(x(points.length - 1), plot.bottom)
      ..lineTo(x(0), plot.bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = chart.withValues(alpha: 0.10));
    canvas.drawPath(
      line,
      Paint()
        ..color = chart
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // End marker with a ring in the page color, labelled with the rating.
    final last = points.length - 1;
    _dot(canvas, Offset(x(last), y(points[last])), chart);
    _text(canvas, '${points[last]}', d.number(13, weight: FontWeight.w700),
        Offset(x(last) + 10, y(points[last])));

    final a = active;
    if (a != null && tooltip != null) {
      final px = x(a);
      canvas.drawLine(
        Offset(px, plot.top),
        Offset(px, plot.bottom),
        Paint()
          ..color = d.muted
          ..strokeWidth = 1,
      );
      _dot(canvas, Offset(px, y(points[a])), chart);
      _tooltip(canvas, size, tooltip!, Offset(px, y(points[a])));
    }
  }

  void _dot(Canvas canvas, Offset c, Color color) {
    canvas.drawCircle(c, 6, Paint()..color = design.background);
    canvas.drawCircle(c, 4, Paint()..color = color);
  }

  void _tooltip(Canvas canvas, Size size, String text, Offset anchor) {
    final d = design;
    final tp = TextPainter(
      text: TextSpan(text: text, style: d.body(13, color: d.background, weight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: 220);
    const pad = 8.0;
    final w = tp.width + pad * 2;
    final h = tp.height + pad * 2;
    final left = (anchor.dx - w / 2).clamp(0.0, size.width - w);
    var top = anchor.dy - h - 12;
    if (top < 0) top = anchor.dy + 12;
    final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, w, h), Radius.circular(d.radius == 0 ? 0 : 6));
    canvas.drawRRect(r, Paint()..color = d.ink);
    tp.paint(canvas, Offset(left + pad, top + pad));
  }

  void _text(Canvas canvas, String s, TextStyle style, Offset at, {bool rightAlign = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)
      ..layout();
    final dx = rightAlign ? at.dx - tp.width : at.dx;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_RatingPainter old) =>
      old.points != points || old.design != design || old.active != active;
}
