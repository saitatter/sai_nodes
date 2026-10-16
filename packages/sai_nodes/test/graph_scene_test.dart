import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';

void main() {
  test(
    'routing geometry drives hit testing and waypoint positions for every route',
    () {
      const engine = ConnectionGeometryEngine();
      for (final routing in ConnectionRouting.values) {
        final geometry = engine.compute(
          const GraphPoint(0, 0),
          const GraphPoint(400, 100),
          routing: routing,
          waypoints: [const GraphPoint(200, -50)],
        );
        expect(geometry.points.first, GraphPoint.zero);
        expect(geometry.points.last, const GraphPoint(400, 100));
        expect(geometry.points, contains(const GraphPoint(200, -50)));
        expect(geometry.distanceTo(geometry.pointAt(.4)), lessThan(.00001));
        expect(
          geometry.distanceTo(const GraphPoint(200, 1000)),
          greaterThan(800),
        );
        expect(geometry.bounds.isValid, true);
      }
    },
  );
  test(
    'spatial buckets match a linear scan and handle negative and oversized bounds',
    () {
      final bounds = {
        for (var i = 0; i < 5000; i++)
          'n$i': GraphRect(
            (i % 100) * 300 - 2000,
            (i ~/ 100) * 200 - 1000,
            260,
            100,
          ),
        'huge': const GraphRect(-1e6, -1e6, 2e6, 2e6),
      };
      final index = GraphSpatialIndex(bounds);
      for (var sample = 0; sample < 20; sample++) {
        final region = GraphRect(
          sample * 100 - 1000,
          sample * 50 - 500,
          700,
          500,
        );
        expect(
          index.query(region),
          bounds.entries
              .where((entry) => entry.value.overlaps(region))
              .map((entry) => entry.key)
              .toSet(),
        );
      }
    },
  );
  test(
    'unknown definitions and dangling endpoints render as repairable scene items',
    () {
      final graph = GraphController(
        document: GraphDocument(
          id: 'd',
          spaces: {
            'main': GraphSpace(
              id: 'main',
              nodes: {'n': GraphNode(id: 'n', type: 'unavailable')},
              connections: {
                'e': GraphConnection(
                  id: 'e',
                  from: const PortRef(nodeId: 'gone', portId: 'out'),
                  to: const PortRef(nodeId: 'n', portId: 'in'),
                  kind: GraphConnectionKind.data,
                ),
              },
            ),
          },
        ),
        resolver: GraphResolver(
          definitions: NodeDefinitionRegistry(),
          types: GraphTypeSystem.core(),
        ),
      );
      addTearDown(graph.dispose);
      final builder = GraphSceneBuilder(),
          scene = GraphSceneBuilder().build(graph);
      expect(scene.nodes['n']!.unresolved, true);
      expect(scene.connections['e']!.invalid, true);
      expect(scene.connections['e']!.geometry.points.isNotEmpty, true);
      final first = builder.build(graph);
      graph.setCamera(const GraphCamera(offset: GraphPoint(100, 200), zoom: 2));
      final second = builder.build(graph);
      expect(second.nodes['n']!.geometry, same(first.nodes['n']!.geometry));
    },
  );
}
