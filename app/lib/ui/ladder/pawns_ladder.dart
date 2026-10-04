import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../../design/design_spec.dart';
import '../../domain/elo.dart';
import '../../domain/models.dart';
import 'ladder_view.dart';

/// Roast pawns: the top eight as one rank of pawns, each filled with coffee up
/// to its rating; everyone who has played is listed below on alternating board
/// squares, and those who have not follow unranked.
class PawnsLadder extends StatelessWidget {
  const PawnsLadder({super.key, required this.data});

  final LadderData data;

  static const _pawnsInARank = 8;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final players = data.ranked;
    // Fill is relative to the furthest anyone has drifted from the start, so
    // pawns stay readable whether the ladder spans 50 points or 500.
    final maxDrift = players.fold(
      100,
      (m, p) => math.max(m, (p.rating - startingRating).abs()),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The ladder', style: d.display(38)),
          const SizedBox(height: 8),
          Text(
            data.summary ?? 'Every player at Awake starts at 1000.',
            style: d.body(16, color: d.muted),
          ),
          if (data.chase case final chase?) ...[
            const SizedBox(height: 6),
            Text(
              chase,
              style: d.body(16, color: d.accent, weight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 24),
          // Nobody has played yet: an empty board would read as a broken top
          // eight, so go straight to the members waiting to play.
          if (players.isEmpty)
            Text('No games yet.', style: d.body(13, color: d.muted))
          else ...[
            // Pawns are a shortcut for tap and keyboard users (each one is a
            // focusable button, Enter or Space opens the profile). They stay
            // out of the semantics tree on purpose: the list below carries the
            // same players with rank and record, and announcing both would
            // read every player twice.
            ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 14, 6, 10),
                decoration: BoxDecoration(
                  color: d.surface,
                  border: Border.all(color: d.ink, width: 2),
                  borderRadius: d.borderRadius,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final p in players.take(_pawnsInARank))
                      Expanded(
                        child: _PawnButton(
                          label: '${p.displayName}, rating ${p.rating}',
                          onOpen: () => data.onOpen(p),
                          child: _Pawn(
                            player: p,
                            fill:
                                0.5 +
                                (p.rating - startingRating) / (2.2 * maxDrift),
                            isMe: p.id == data.meId,
                          ),
                        ),
                      ),
                    // Keep pawn width constant on short ladders.
                    for (var i = players.length; i < _pawnsInARank; i++)
                      const Spacer(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Awake\'s top eight. The fuller the pawn, the higher the rating.',
              style: d.body(13, color: d.muted),
            ),
          ],
          const SizedBox(height: 20),
          for (final (i, p) in players.indexed)
            LadderRowTap(
              player: p,
              data: data,
              rank: i + 1,
              child: _Row(player: p, rank: i + 1, isMe: p.id == data.meId),
            ),
          UnplayedGroup(data: data),
        ],
      ),
    );
  }
}

/// Makes a pawn a keyboard-reachable button: it takes Tab focus, Enter or
/// Space opens the profile, and a ring in the design's accent shows where
/// focus is. The tooltip names the player and rating on hover, long-press and
/// keyboard focus.
class _PawnButton extends StatefulWidget {
  const _PawnButton({
    required this.label,
    required this.onOpen,
    required this.child,
  });

  final String label;
  final VoidCallback onOpen;
  final Widget child;

  @override
  State<_PawnButton> createState() => _PawnButtonState();
}

class _PawnButtonState extends State<_PawnButton> {
  /// The pawn whose tooltip keyboard focus opened. Focus moving between pawns
  /// notifies both in no fixed order, so only this one may close it.
  static _PawnButtonState? _tooltipOwner;

  final _tooltip = GlobalKey<TooltipState>();

  /// True only for keyboard focus, so a mouse click leaves no ring behind.
  bool _ring = false;

  /// Material tooltips open on hover and long-press only, so a keyboard user
  /// would see the ring but never the rating without this.
  void _onHighlight(bool shown) {
    setState(() => _ring = shown);
    if (shown) {
      Tooltip.dismissAllToolTips();
      _tooltip.currentState?.ensureTooltipVisible();
      _tooltipOwner = this;
    } else if (_tooltipOwner == this) {
      Tooltip.dismissAllToolTips();
      _tooltipOwner = null;
    }
  }

  @override
  void dispose() {
    if (_tooltipOwner == this) _tooltipOwner = null;
    super.dispose();
  }

  void _open() => widget.onOpen();

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Tooltip(
      key: _tooltip,
      message: widget.label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: _onHighlight,
        // The web build maps Enter to ButtonActivateIntent and Space to
        // ActivateIntent; other platforms map both to ActivateIntent.
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _open(),
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) => _open(),
          ),
        },
        child: GestureDetector(
          onTap: _open,
          // Foreground and padded, so the name label (accent on your own
          // pawn) neither paints over the ring nor blends into it.
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(
                color: _ring ? d.accent : Colors.transparent,
                width: 2.5,
              ),
              borderRadius: d.borderRadius,
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _Pawn extends StatelessWidget {
  const _Pawn({required this.player, required this.fill, required this.isMe});

  final Player player;
  final double fill;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 40),
            child: AspectRatio(
              aspectRatio: 40 / 60,
              child: CustomPaint(
                painter: _PawnPainter(design: d, fill: fill.clamp(0.04, 1)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: isMe ? d.accent : null,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              player.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: d.body(
                11,
                weight: FontWeight.w700,
                color: isMe ? d.onAccent : d.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.player, required this.rank, required this.isMe});

  final Player player;
  final int rank;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final lightSquare = rank.isOdd;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: isMe ? d.highlight : null,
        border: Border(
          left: BorderSide(
            color: isMe ? d.accent : Colors.transparent,
            width: 3,
          ),
          bottom: BorderSide(color: d.surface),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            color: lightSquare ? d.ink : d.surface,
            child: Text(
              '$rank',
              style: d.number(
                14,
                weight: FontWeight.w700,
                color: lightSquare ? d.background : d.ink,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${player.displayName} (you)' : player.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: d.body(16, weight: FontWeight.w700),
                ),
                Text(
                  '${player.gamesPlayed} games, ${record(player)}',
                  style: d.number(12, color: d.muted),
                ),
              ],
            ),
          ),
          Text('${player.rating}', style: d.number(22, displayFace: true)),
        ],
      ),
    );
  }
}

/// A pawn in a 40×60 box: head, collar, body, base.
class _PawnPainter extends CustomPainter {
  _PawnPainter({required this.design, required this.fill});

  final DesignSpec design;

  /// 0 is empty, 1 is full to the top of the head.
  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    final d = design;
    canvas.scale(size.width / 40, size.height / 60);
    final pawn = Path()
      ..addOval(Rect.fromCircle(center: const Offset(20, 11), radius: 8))
      ..addPolygon(const [
        Offset(13, 21),
        Offset(27, 21),
        Offset(25, 25),
        Offset(15, 25),
      ], true)
      ..addPolygon(const [
        Offset(15, 25),
        Offset(25, 25),
        Offset(29, 47),
        Offset(11, 47),
      ], true)
      ..addRRect(RRect.fromLTRBR(6, 47, 34, 56, const Radius.circular(2)));

    canvas.drawPath(pawn, Paint()..color = d.background);
    canvas.save();
    canvas.clipPath(pawn);
    final surfaceY = 56 - fill * 53;
    canvas.drawRect(
      Rect.fromLTRB(0, surfaceY, 40, 60),
      Paint()..color = d.accent,
    );
    // Milk foam on top of the pour.
    canvas.drawRect(
      Rect.fromLTRB(0, surfaceY, 40, surfaceY + 2.5),
      Paint()..color = d.ink,
    );
    canvas.restore();
    canvas.drawPath(
      pawn,
      Paint()
        ..color = d.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_PawnPainter old) =>
      old.design != design || old.fill != fill;
}
