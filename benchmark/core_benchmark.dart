import 'dart:convert';
import 'dart:io';
import 'package:sai_nodes_core/sai_nodes_core.dart';

GraphDocument benchmarkDocument(int count) => GraphDocument(
  id: 'benchmark',
  spaces: {
    'main': GraphSpace(
      id: 'main',
      nodes: {
        for (var i = 0; i < count; i++)
          'n$i': GraphNode(
            id: 'n$i',
            type: i % 10 == 0 ? 'dynamic' : 'number',
            data: {'value': i, 'ports': 2},
          ),
      },
      connections: {
        for (var i = 1; i < count; i++)
          'e$i': GraphConnection(
            id: 'e$i',
            from: PortRef(nodeId: 'n${i - 1}', portId: 'value.out'),
            to: PortRef(nodeId: 'n$i', portId: 'value.in'),
            kind: GraphConnectionKind.data,
          ),
      },
      nodePresentations: {
        for (var i = 0; i < count; i++)
          'n$i': NodePresentation(
            nodeId: 'n$i',
            position: GraphPoint((i % 50) * 320, (i ~/ 50) * 180),
          ),
      },
    ),
  },
);
NodeDefinitionRegistry benchmarkDefinitions() {
  final definitions = NodeDefinitionRegistry();
  final ports = StaticPortFamily([
    ResolvedPort(
      id: 'value.in',
      direction: GraphPortDirection.input,
      kind: GraphPortKind.data,
      dataType: 'core.number',
      label: 'Value',
      maxConnections: 1,
    ),
    ResolvedPort(
      id: 'value.out',
      direction: GraphPortDirection.output,
      kind: GraphPortKind.data,
      dataType: 'core.number',
      label: 'Value',
    ),
  ]);
  definitions.register(
    DeclarativeNodeDefinition(
      type: 'number',
      displayName: 'Number',
      ports: [ports],
    ),
  );
  definitions.register(
    DeclarativeNodeDefinition(
      type: 'dynamic',
      displayName: 'Dynamic',
      ports: [
        ports,
        DynamicPortFamily(
          (context) => [
            for (var i = 0; i < (context.node.data['ports'] as int? ?? 0); i++)
              ResolvedPort(
                id: 'extra:$i',
                direction: GraphPortDirection.output,
                kind: GraphPortKind.data,
                label: '$i',
                dataType: 'core.number',
              ),
          ],
        ),
      ],
    ),
  );
  return definitions;
}

void main(List<String> arguments) {
  final sizes =
      arguments
          .where((value) => value.startsWith('--sizes='))
          .firstOrNull
          ?.substring(8)
          .split(',')
          .map(int.parse)
          .toList() ??
      [100, 500, 1000, 3000, 5000];
  final samples = int.parse(
    arguments
            .where((value) => value.startsWith('--samples='))
            .firstOrNull
            ?.substring(10) ??
        '5',
  );
  final report = <String, Object?>{};
  for (final count in sizes) {
    final measurements = <String, List<double>>{};
    T measure<T>(String name, T Function() operation) {
      final clock = Stopwatch()..start();
      final result = operation();
      clock.stop();
      (measurements[name] ??= []).add(clock.elapsedMicroseconds / 1000);
      return result;
    }

    for (var sample = 0; sample < samples; sample++) {
      final document = measure('model', () => benchmarkDocument(count));
      final resolver = GraphResolver(
        definitions: benchmarkDefinitions(),
        types: GraphTypeSystem.core(),
      );
      measure('resolution', () => resolver.resolve(document));
      measure(
        'indexes',
        () => GraphIndexes.fromSpace(document.spaces['main']!),
      );
      final controller = GraphController(
        document: document,
        resolver: resolver,
      );
      measure(
        'dynamic_resolution',
        () => controller.execute(
          const UpdateNodeDataCommand('main', 'n0', {'value': 0, 'ports': 3}),
        ),
      );
      measure(
        'node_move',
        () => controller.execute(
          MoveNodesCommand('main', {'n0': const GraphPoint(10, 10)}),
        ),
      );
      measure('undo', controller.undo);
      measure('redo', controller.redo);
      controller.selectAll();
      final fragment = measure(
        'clipboard_copy',
        () => GraphFragment.capture(controller),
      );
      measure('clipboard_paste', () => controller.pasteGraphFragment(fragment));
      final geometry = const NodeGeometryEngine();
      final space = controller.activeSpace!;
      final bounds = {
        for (final node in space.nodes.values)
          node.id: geometry
              .compute(
                space.nodePresentations[node.id]!,
                controller.resolution.structures['main']?[node.id],
              )
              .bounds,
      };
      measure(
        'marquee',
        () => controller.marquee(const GraphRect(0, 0, 1000, 1000), bounds),
      );
      controller.dispose();
    }
    report['$count'] = {
      for (final entry in measurements.entries) entry.key: summary(entry.value),
    };
    stdout.writeln('$count nodes: ${jsonEncode(report['$count'])}');
  }
  final directory = Directory('.tmp/benchmarks')..createSync(recursive: true);
  File('${directory.path}/core.json').writeAsStringSync(
    const JsonEncoder.withIndent(
      '  ',
    ).convert({'samples': samples, 'milliseconds': report}),
  );
}

Map<String, Object> summary(List<double> values) {
  final sorted = [...values]..sort();
  return {
    'median': sorted[sorted.length ~/ 2],
    'p95':
        sorted[((sorted.length * .95).ceil() - 1).clamp(0, sorted.length - 1)],
    'samples': values,
  };
}
