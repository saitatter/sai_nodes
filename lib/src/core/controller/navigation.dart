import '../models/data.dart';

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

    final delta = candidate.offset - current.offset;
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
