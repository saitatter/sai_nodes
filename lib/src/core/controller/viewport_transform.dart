import 'package:flutter/widgets.dart';

/// Converts between local editor-screen coordinates and node-world
/// coordinates.
///
/// The editor renders its world with the origin at the center of the viewport.
/// [viewportOffset] is the world translation used by the editor and [zoom] is
/// the scale applied to world units.
final class NodeEditorViewportTransform {
  const NodeEditorViewportTransform({
    required this.viewportSize,
    required this.viewportOffset,
    required this.zoom,
  }) : assert(zoom > 0);

  final Size viewportSize;
  final Offset viewportOffset;
  final double zoom;

  Offset screenToWorld(Offset screenPosition) => Offset(
        (screenPosition.dx - viewportSize.width / 2) / zoom - viewportOffset.dx,
        (screenPosition.dy - viewportSize.height / 2) / zoom -
            viewportOffset.dy,
      );

  Offset worldToScreen(Offset worldPosition) => Offset(
        viewportSize.width / 2 + (worldPosition.dx + viewportOffset.dx) * zoom,
        viewportSize.height / 2 + (worldPosition.dy + viewportOffset.dy) * zoom,
      );

  Rect get visibleWorldBounds => Rect.fromLTWH(
        -viewportSize.width / (2 * zoom) - viewportOffset.dx,
        -viewportSize.height / (2 * zoom) - viewportOffset.dy,
        viewportSize.width / zoom,
        viewportSize.height / zoom,
      );
}
