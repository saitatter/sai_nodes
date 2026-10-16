import 'dart:math' as math;
import 'package:sai_nodes_core/sai_nodes_core.dart';

enum ConnectionRouting { straight, bezier, orthogonal }

final class ConnectionGeometry {
  ConnectionGeometry(Iterable<GraphPoint> points)
    : points = List.unmodifiable(points) {
    var left = double.infinity,
        top = double.infinity,
        right = -double.infinity,
        bottom = -double.infinity;
    var length = 0.0;
    final cumulative = <double>[0];
    for (final entry in this.points.indexed) {
      final point = entry.$2;
      left = math.min(left, point.x);
      top = math.min(top, point.y);
      right = math.max(right, point.x);
      bottom = math.max(bottom, point.y);
      if (entry.$1 > 0) {
        length += point.distanceTo(this.points[entry.$1 - 1]);
        cumulative.add(length);
      }
    }
    bounds = this.points.isEmpty
        ? const GraphRect(0, 0, 0, 0)
        : GraphRect(left, top, right - left, bottom - top);
    _lengths = List.unmodifiable(cumulative);
    _length = length;
  }
  final List<GraphPoint> points;
  late final GraphRect bounds;
  late final List<double> _lengths;
  late final double _length;
  GraphPoint pointAt(double progress) {
    if (points.isEmpty) return GraphPoint.zero;
    final distance = progress.clamp(0, 1) * _length;
    for (var i = 1; i < points.length; i++) {
      if (_lengths[i] >= distance) {
        final span = _lengths[i] - _lengths[i - 1];
        final t = span == 0 ? 0 : (distance - _lengths[i - 1]) / span;
        return points[i - 1] + (points[i] - points[i - 1]).scale(t.toDouble());
      }
    }
    return points.last;
  }

  double distanceTo(GraphPoint point) {
    var distance = double.infinity;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final dx = b.x - a.x, dy = b.y - a.y;
      final length = dx * dx + dy * dy;
      final t = length == 0
          ? 0.0
          : (((point.x - a.x) * dx + (point.y - a.y) * dy) / length).clamp(
              0.0,
              1.0,
            );
      distance = math.min(
        distance,
        point.distanceTo(GraphPoint(a.x + dx * t, a.y + dy * t)),
      );
    }
    return distance;
  }
}

final class ConnectionGeometryEngine {
  const ConnectionGeometryEngine();
  ConnectionGeometry compute(
    GraphPoint from,
    GraphPoint to, {
    ConnectionRouting routing = ConnectionRouting.bezier,
    List<GraphPoint> waypoints = const [],
  }) {
    final anchors = [from, ...waypoints, to];
    final points = <GraphPoint>[from];
    for (var i = 1; i < anchors.length; i++) {
      final a = anchors[i - 1], b = anchors[i];
      switch (routing) {
        case ConnectionRouting.straight:
          points.add(b);
        case ConnectionRouting.orthogonal:
          final x = (a.x + b.x) / 2;
          points.addAll([GraphPoint(x, a.y), GraphPoint(x, b.y), b]);
        case ConnectionRouting.bezier:
          final delta = math.max(40.0, (b.x - a.x).abs() * .5);
          final c1 = GraphPoint(a.x + delta, a.y),
              c2 = GraphPoint(b.x - delta, b.y);
          for (var sample = 1; sample <= 24; sample++) {
            final t = sample / 24, s = 1 - t;
            points.add(
              a.scale(s * s * s) +
                  c1.scale(3 * s * s * t) +
                  c2.scale(3 * s * t * t) +
                  b.scale(t * t * t),
            );
          }
      }
    }
    return ConnectionGeometry(points);
  }
}

/// Grid buckets accelerate viewport queries; oversized entities use one fallback set.
final class GraphSpatialIndex {
  GraphSpatialIndex(Map<String, GraphRect> bounds, {this.cellSize = 256})
    : bounds = Map.unmodifiable(bounds) {
    if (!cellSize.isFinite || cellSize <= 0) {
      throw ArgumentError('Invalid spatial cell size.');
    }
    for (final entry in bounds.entries) {
      if (!entry.value.isValid) continue;
      final cells = _cells(entry.value);
      if (cells == null) {
        _oversized.add(entry.key);
        continue;
      }
      for (final cell in cells) {
        (_buckets[cell] ??= {}).add(entry.key);
      }
    }
  }
  final Map<String, GraphRect> bounds;
  final double cellSize;
  final Map<(int, int), Set<String>> _buckets = {};
  final Set<String> _oversized = {};
  List<(int, int)>? _cells(GraphRect rect) {
    final l = (rect.left / cellSize).floor(),
        r = (rect.right / cellSize).floor(),
        t = (rect.top / cellSize).floor(),
        b = (rect.bottom / cellSize).floor();
    if ((r - l + 1) * (b - t + 1) > 4096) return null;
    return [
      for (var x = l; x <= r; x++)
        for (var y = t; y <= b; y++) (x, y),
    ];
  }

  Set<String> query(GraphRect rect) {
    if (!rect.isValid) return {};
    final cells = _cells(rect);
    final candidates = cells == null
        ? bounds.keys.toSet()
        : <String>{..._oversized, for (final cell in cells) ...?_buckets[cell]};
    return candidates.where((id) => bounds[id]!.overlaps(rect)).toSet();
  }
}

final class GraphNodeViewModel {
  const GraphNodeViewModel({
    required this.node,
    required this.presentation,
    required this.structure,
    required this.geometry,
    required this.label,
    required this.style,
    required this.unresolved,
  });
  final GraphNode node;
  final NodePresentation presentation;
  final NodeStructure? structure;
  final NodeGeometry geometry;
  final String label;
  final NodeVisualStyle style;
  final bool unresolved;
}

final class GraphConnectionViewModel {
  const GraphConnectionViewModel({
    required this.connection,
    required this.presentation,
    required this.geometry,
    required this.invalid,
    required this.label,
  });
  final GraphConnection connection;
  final ConnectionPresentation presentation;
  final ConnectionGeometry geometry;
  final bool invalid;
  final String? label;
}

final class GraphScene {
  GraphScene({
    required this.spaceId,
    required Map<String, GraphNodeViewModel> nodes,
    required Map<String, GraphConnectionViewModel> connections,
    required this.space,
  }) : nodes = Map.unmodifiable(nodes),
       connections = Map.unmodifiable(connections),
       nodeIndex = GraphSpatialIndex(
         nodes.map((id, node) => MapEntry(id, node.geometry.bounds)),
       ),
       connectionIndex = GraphSpatialIndex(
         connections.map(
           (id, edge) => MapEntry(id, edge.geometry.bounds.inflate(10)),
         ),
       ),
       frameIndex = GraphSpatialIndex(
         space.frames.map((id, frame) => MapEntry(id, frame.bounds)),
       );
  final String spaceId;
  final GraphSpace space;
  final Map<String, GraphNodeViewModel> nodes;
  final Map<String, GraphConnectionViewModel> connections;
  final GraphSpatialIndex nodeIndex, connectionIndex, frameIndex;
  GraphRect get bounds =>
      [
        ...nodes.values.map((node) => node.geometry.bounds),
        ...space.frames.values.map((frame) => frame.bounds),
        ...space.comments.values.map((comment) => comment.bounds),
      ].fold<GraphRect?>(null, (rect, next) => rect?.union(next) ?? next) ??
      const GraphRect(0, 0, 0, 0);
  GraphNodeViewModel? hitNode(GraphPoint point) {
    final ids = nodeIndex.query(GraphRect(point.x, point.y, 0, 0));
    return nodes.values.where((node) => ids.contains(node.node.id)).lastOrNull;
  }

  GraphConnectionViewModel? hitConnection(
    GraphPoint point, {
    double tolerance = 8,
  }) {
    final ids = connectionIndex.query(
      GraphRect(
        point.x - tolerance,
        point.y - tolerance,
        tolerance * 2,
        tolerance * 2,
      ),
    );
    GraphConnectionViewModel? closest;
    var distance = tolerance;
    for (final id in ids) {
      final edge = connections[id]!;
      final next = edge.geometry.distanceTo(point);
      if (next <= distance) {
        closest = edge;
        distance = next;
      }
    }
    return closest;
  }
}

/// Reuses node geometry across camera/selection/execution changes and unchanged nodes.
final class GraphSceneBuilder {
  GraphSceneBuilder({
    this.nodes = const NodeGeometryEngine(),
    this.connections = const ConnectionGeometryEngine(),
  });
  final NodeGeometryEngine nodes;
  final ConnectionGeometryEngine connections;
  final Map<String, (NodePresentation, NodeStructure?, NodeGeometry)>
  _nodeCache = {};
  final Map<
    String,
    (
      GraphPoint,
      GraphPoint,
      ConnectionPresentation,
      ConnectionRouting,
      ConnectionGeometry,
    )
  >
  _connectionCache = {};
  GraphScene build(
    GraphController controller, {
    ConnectionRouting routing = ConnectionRouting.bezier,
    String? Function(GraphConnection)? connectionLabel,
  }) {
    final space = controller.activeSpace;
    if (space == null) {
      return GraphScene(
        spaceId: '',
        nodes: {},
        connections: {},
        space: GraphSpace(id: ''),
      );
    }
    final models = <String, GraphNodeViewModel>{};
    final structures = controller.resolution.structures[space.id] ?? {};
    for (final node in space.nodes.values) {
      final view =
          space.nodePresentations[node.id] ??
          NodePresentation(nodeId: node.id, position: GraphPoint.zero);
      final structure = structures[node.id];
      final cached = _nodeCache[node.id];
      final geometry =
          cached != null && cached.$1 == view && cached.$2 == structure
          ? cached.$3
          : nodes.compute(view, structure);
      _nodeCache[node.id] = (view, structure, geometry);
      final definition = controller.resolver.definitions[node.type];
      models[node.id] = GraphNodeViewModel(
        node: node,
        presentation: view,
        structure: structure,
        geometry: geometry,
        label:
            view.title ??
            definition?.label(
              NodeDefinitionContext(
                document: controller.document,
                space: space,
                node: node,
              ),
            ) ??
            node.type,
        style:
            definition?.style(
              NodeVisualContext(
                document: controller.document,
                space: space,
                node: node,
              ),
            ) ??
            const NodeVisualStyle(color: 0xffef4444),
        unresolved: definition == null || structure == null,
      );
    }
    _nodeCache.removeWhere((id, _) => !models.containsKey(id));
    final invalid = controller.resolution.diagnostics
        .where(
          (issue) =>
              issue.spaceId == space.id &&
              issue.kind == GraphEntityKind.connection,
        )
        .map((issue) => issue.entityId)
        .toSet();
    final edges = <String, GraphConnectionViewModel>{};
    for (final edge in space.connections.values) {
      final source = models[edge.from.nodeId], target = models[edge.to.nodeId];
      final from =
          source?.geometry.ports[edge.from.portId] ??
          source?.geometry.bounds.center;
      final to =
          target?.geometry.ports[edge.to.portId] ??
          target?.geometry.bounds.center;
      // Missing-node endpoints stay visible near their surviving endpoint.
      final origin =
          from ?? ((to ?? GraphPoint.zero) - const GraphPoint(100, 40));
      final destination = to ?? (origin + const GraphPoint(100, 40));
      final view =
          space.connectionPresentations[edge.id] ??
          ConnectionPresentation(connectionId: edge.id);
      final cached = _connectionCache[edge.id];
      final geometry =
          cached != null &&
              cached.$1 == origin &&
              cached.$2 == destination &&
              cached.$3 == view &&
              cached.$4 == routing
          ? cached.$5
          : connections.compute(
              origin,
              destination,
              routing: routing,
              waypoints: view.waypoints,
            );
      _connectionCache[edge.id] = (
        origin,
        destination,
        view,
        routing,
        geometry,
      );
      edges[edge.id] = GraphConnectionViewModel(
        connection: edge,
        presentation: view,
        geometry: geometry,
        invalid: invalid.contains(edge.id),
        label: view.label ?? connectionLabel?.call(edge),
      );
    }
    _connectionCache.removeWhere((id, _) => !edges.containsKey(id));
    return GraphScene(
      spaceId: space.id,
      nodes: models,
      connections: edges,
      space: space,
    );
  }
}
