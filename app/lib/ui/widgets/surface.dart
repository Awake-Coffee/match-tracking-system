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
