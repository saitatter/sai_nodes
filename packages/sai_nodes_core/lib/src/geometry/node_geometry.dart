import 'dart:math' as math;
import '../definitions/node_definition.dart';
import '../model/graph_document.dart';
import 'geometry.dart';

final class NodeGeometry {
  NodeGeometry({required this.bounds, required Map<String, GraphPoint> ports})
    : ports = Map.unmodifiable(ports);
  final GraphRect bounds;
  final Map<String, GraphPoint> ports;
}

final class NodeGeometryEngine {
  const NodeGeometryEngine({
    this.defaultWidth = 260,
    this.headerHeight = 38,
    this.rowHeight = 28,
    this.fieldHeight = 36,
  });
  final double defaultWidth, headerHeight, rowHeight, fieldHeight;
  NodeGeometry compute(NodePresentation view, NodeStructure? structure) {
    final ports = structure?.ports ?? [];
    final inputs = ports
        .where((port) => port.direction == GraphPortDirection.input)
        .toList();
    final outputs = ports
        .where((port) => port.direction == GraphPortDirection.output)
        .toList();
    final rows = math.max(inputs.length, outputs.length);
    final fields =
        structure?.fields
            .where((field) => field.metadata['placement'] != 'inspector')
            .length ??
        0;
    final width = view.size?.width ?? defaultWidth;
    final height = view.collapsed
        ? headerHeight
        : math.max(
            view.size?.height ?? 0,
            headerHeight +
                rows * rowHeight +
                fields * fieldHeight +
                (structure == null ? 40 : 12),
          );
    final bounds = GraphRect(view.position.x, view.position.y, width, height);
    return NodeGeometry(
      bounds: bounds,
      ports: {
        for (final entry in inputs.indexed)
          entry.$2.id: GraphPoint(
            bounds.left,
            view.collapsed
                ? bounds.center.y
                : bounds.top + headerHeight + (entry.$1 + .5) * rowHeight,
          ),
        for (final entry in outputs.indexed)
          entry.$2.id: GraphPoint(
            bounds.right,
            view.collapsed
                ? bounds.center.y
                : bounds.top + headerHeight + (entry.$1 + .5) * rowHeight,
          ),
      },
    );
  }
}
