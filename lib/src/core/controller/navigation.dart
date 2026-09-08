import '../models/data.dart';
import 'package:flutter/rendering.dart';

Offset _center(NodeDataModel node) {
  // Navigation is also used by headless hosts and unit tests, where Flutter's
  // widget binding may not exist yet. Accessing GlobalKey.currentContext in
  // that state throws before it can return null, so keep the optional layout
  // lookup guarded and fall back to the persisted/custom geometry.
  RenderBox? box;
  try {
    box = node.key.currentContext?.findRenderObject() as RenderBox?;
  } on Object {
    box = null;
  }
  final size =
      box != null && box.hasSize ? box.size : node.customSize ?? Size.zero;
  return node.offset + size.center(Offset.zero);
}

/// The geometric direction used by keyboard or accessibility navigation.
enum NodeNavigationDirection { left, right, up, down }

/// Finds the closest node in [direction] from [current].
///
/// The score prefers nodes that are close on the primary axis, while still
/// allowing navigation between rows and columns that are not perfectly
/// aligned. The controller is responsible for applying the resulting
/// selection.
NodeDataModel? findNearestNodeInDirection(
  Iterable<NodeDataModel> nodes,
  NodeDataModel current,
  NodeNavigationDirection direction, {
  double minPrimaryDistance = 20,
}) {
  assert(minPrimaryDistance >= 0);

  NodeDataModel? best;
  var bestScore = double.infinity;
  for (final candidate in nodes) {
    if (candidate.id == current.id) continue;

    final delta = _center(candidate) - _center(current);
    final inDirection = switch (direction) {
      NodeNavigationDirection.right => delta.dx > minPrimaryDistance,
      NodeNavigationDirection.left => delta.dx < -minPrimaryDistance,
      NodeNavigationDirection.down => delta.dy > minPrimaryDistance,
      NodeNavigationDirection.up => delta.dy < -minPrimaryDistance,
    };
    if (!inDirection) continue;

    final primaryDistance = switch (direction) {
      NodeNavigationDirection.right => delta.dx,
      NodeNavigationDirection.left => -delta.dx,
      NodeNavigationDirection.down => delta.dy,
      NodeNavigationDirection.up => -delta.dy,
    };
    final crossDistance = direction == NodeNavigationDirection.left ||
            direction == NodeNavigationDirection.right
        ? delta.dy.abs()
        : delta.dx.abs();
    final score = primaryDistance + crossDistance * 2;
    if (score < bestScore) {
      bestScore = score;
      best = candidate;
    }
  }

  return best;
}
