import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../../domain/models.dart';

/// Who a tile shows: their photo, or the initial of [name] when [url] is null.
typedef Face = ({String name, String? url});

extension PlayerFace on Player {
  Face get face => (name: displayName, url: avatarUrl);
}

/// A member's profile photo as a square tile. Without one, or while it fails
/// to load, the tile is the board inverted with the first letter of their
/// name. Always sits beside the name, so screen readers skip it.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.face, required this.size});

  final Face face;
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final initial = ColoredBox(
      color: d.ink,
      child: Center(
        child: Text(
          face.name.characters.firstOrNull?.toUpperCase() ?? '',
          style: d.display(size * 0.5, color: d.background, height: 1),
        ),
      ),
    );
    final url = face.url;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: d.borderRadius,
          child: url == null
              ? initial
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => initial,
                ),
        ),
      ),
    );
  }
}

/// Up to two players' tiles overlapping, at the head of a result. Each is
/// ringed in [ring], the color behind the row, so the overlap reads.
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.faces, this.ring});

  final List<Face> faces;

  /// The background's color when null.
  final Color? ring;

  static const _size = 36.0;
  static const _ringWidth = 2.0;
  static const _overlap = 10.0;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final shown = faces.take(2).toList();
    const step = _size + _ringWidth * 2 - _overlap;
    return SizedBox(
      width: step * (shown.length - 1) + _size + _ringWidth * 2,
      height: _size + _ringWidth * 2,
      child: Stack(
        children: [
          for (final (i, face) in shown.indexed)
            Positioned(
              left: step * i,
              child: Container(
                padding: const EdgeInsets.all(_ringWidth),
                decoration: BoxDecoration(
                  color: ring ?? d.background,
                  borderRadius: d.borderRadius,
                ),
                child: Avatar(face: face, size: _size),
              ),
            ),
        ],
      ),
    );
  }
}
