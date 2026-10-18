import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';
import 'package:sai_nodes_example/gallery/catalog.dart';
import 'package:sai_nodes_example/gallery/runtime.dart';

void main() {
  GraphDemo demo(String id) => graphDemos.singleWhere((demo) => demo.id == id);
  test('structural maps expose projection instead of execution', () {
    final item = demo('mindmap');
    final runtime = DemoRuntime(item, item.document());
    expect(runtime.run, throwsStateError);
    expect(runtime.projectStructure().outputs.length, item.nodes.length);
    final graph = item.controller();
    addTearDown(graph.dispose);
    final ports = graph.resolution.structures[gallerySpace]!.values.expand(
      (structure) => structure.ports,
    );
    expect(ports.every((port) => port.dataType == 'demo.idea'), true);
  });
  for (final item in graphDemos) {
    test(
      '${item.id}: typed starter resolves, fits without overlaps, and runs after JSON round-trip',
      () {
        final graph = item.controller();
        addTearDown(graph.dispose);
        expect(graph.resolution.diagnostics, isEmpty);
        final document = GraphDocument.fromJson(graph.document.toJson());
        final runtime = DemoRuntime(item, document);
        final result = item.isStructural
            ? runtime.projectStructure()
            : runtime.run();
        expect(result.outputs.length, item.nodes.length);
        expect(result.connections.length, item.edges.length);
        final nodes = GraphSceneBuilder().build(graph).nodes.values.toList();
        for (var i = 0; i < nodes.length; i++) {
          for (var j = i + 1; j < nodes.length; j++) {
            expect(
              nodes[i].geometry.bounds
                  .inflate(10)
                  .overlaps(nodes[j].geometry.bounds),
              false,
              reason: '${nodes[i].node.id} overlaps ${nodes[j].node.id}',
            );
          }
        }
      },
    );
  }
  test('game gates jumping and undo restores the previous result', () {
    final item = demo('game'), graph = item.controller();
    addTearDown(graph.dispose);
    expect(
      (DemoRuntime(item, graph.document).run().value as Map)['jumped'],
      true,
    );
    graph.execute(
      const UpdateNodeDataCommand(gallerySpace, 'grounded', {'value': false}),
    );
    expect(
      (DemoRuntime(item, graph.document).run().value as Map)['velocity'],
      0,
    );
    graph.undo();
    expect(
      (DemoRuntime(item, graph.document).run().value as Map)['jumped'],
      true,
    );
  });
  test('workflow takes both approval paths, including the exact limit', () {
    final item = demo('workflow'), graph = item.controller();
    addTearDown(graph.dispose);
    expect(
      (DemoRuntime(item, graph.document).run().value as Map)['approved'],
      true,
    );
    graph.execute(
      const UpdateNodeDataCommand(gallerySpace, 'expense', {'value': 500.0}),
    );
    expect(
      (DemoRuntime(item, graph.document).run().value as Map)['approved'],
      false,
    );
  });
  test('dataflow filters, normalizes and handles empty output', () {
    final item = demo('data'), graph = item.controller();
    addTearDown(graph.dispose);
    var value = DemoRuntime(item, graph.document).run().value as Map;
    expect(value['count'], 3);
    expect((value['rows'] as List).first['normalized'], .92);
    graph.execute(
      const UpdateNodeDataCommand(gallerySpace, 'filter', {'minimum': 100.0}),
    );
    value = DemoRuntime(item, graph.document).run().value as Map;
    expect(value['count'], 0);
    expect(value['average'], 0);
  });
  test('ML inference computes matrix products, bias, ReLU and sigmoid', () {
    final item = demo('ml'), graph = item.controller();
    addTearDown(graph.dispose);
    final value = DemoRuntime(item, graph.document).run().value as Map;
    expect(value['logit'], closeTo(.68, 1e-10));
    expect(value['probability'], closeTo(1 / (1 + math.exp(-.68)), 1e-10));
    graph.execute(
      const UpdateNodeDataCommand(gallerySpace, 'hidden', {
        'weights': [
          [1],
        ],
        'bias': [0],
      }, merge: true),
    );
    expect(
      () => DemoRuntime(item, graph.document).run(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('columns'),
        ),
      ),
    );
  });
  test('shader parameters affect generated GLSL without changing topology', () {
    final item = demo('shader'), graph = item.controller();
    addTearDown(graph.dispose);
    final before =
        (DemoRuntime(item, graph.document).run().value as Map)['glsl'];
    graph.execute(
      const UpdateNodeDataCommand(gallerySpace, 'wave', {
        'frequency': 12.0,
      }, merge: true),
    );
    final after =
        (DemoRuntime(item, graph.document).run().value as Map)['glsl'];
    expect(after, isNot(before));
    expect(after, contains('12.000'));
    expect(graph.activeSpace!.connections.length, item.edges.length);
  });
  test(
    'audio follows connected signal properties and enforces gain bounds',
    () {
      final item = demo('audio'), graph = item.controller();
      addTearDown(graph.dispose);
      final value = DemoRuntime(item, graph.document).run().value as Map;
      expect(value, {
        'frequency': 220.0,
        'waveform': 'sine',
        'gain': .08,
        'cutoff': 900.0,
      });
      graph.execute(
        const UpdateNodeDataCommand(gallerySpace, 'gain', {'gain': 10}),
      );
      expect(() => DemoRuntime(item, graph.document).run(), throwsStateError);
    },
  );
  test(
    'missing wires and cyclic idea branches fail with actionable errors',
    () {
      final item = demo('game'), graph = item.controller();
      addTearDown(graph.dispose);
      graph.execute(RemoveNodesCommand(gallerySpace, {'input'}));
      expect(
        () => DemoRuntime(item, graph.document).run(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Connect exactly one'),
          ),
        ),
      );
      final ideas = demo('mindmap'), ideaGraph = ideas.controller();
      addTearDown(ideaGraph.dispose);
      final space = ideaGraph.activeSpace!;
      final cyclic = ideaGraph.document.copyWith(
        spaces: {
          gallerySpace: space.copyWith(
            connections: {
              ...space.connections,
              'cycle': GraphConnection(
                id: 'cycle',
                from: const PortRef(nodeId: 'types', portId: 'out'),
                to: const PortRef(nodeId: 'idea', portId: 'in:parent'),
                kind: GraphConnectionKind.data,
              ),
            },
          ),
        },
      );
      expect(
        () => DemoRuntime(ideas, cyclic).projectStructure(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('cycle'),
          ),
        ),
      );
    },
  );
}
