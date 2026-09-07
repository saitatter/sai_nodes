import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Fits world-space bounds into a minimap without changing aspect ratio.
/// Hosts supply node/frame bounds and clip painting to [size].
final class NodeEditorMinimapTransform {
  NodeEditorMinimapTransform({
    required this.bounds,
    required this.size,
    this.padding = 12,
  })  : assert(size.width > padding * 2 && size.height > padding * 2),
        assert(padding >= 0);

  final Rect bounds;
  final Size size;
  final double padding;

  double get scale => math.min(
        (size.width - 2 * padding) / math.max(1, bounds.width),
        (size.height - 2 * padding) / math.max(1, bounds.height),
      );

  Offset get _origin => size.center(Offset.zero) - bounds.center * scale;
  Offset worldToMinimap(Offset point) => point * scale + _origin;
  Offset minimapToWorld(Offset point) => (point - _origin) / scale;
  Rect worldRectToMinimap(Rect rect) => Rect.fromPoints(
        worldToMinimap(rect.topLeft),
        worldToMinimap(rect.bottomRight),
      );
}
