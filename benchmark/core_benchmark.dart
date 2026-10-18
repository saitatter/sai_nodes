import 'dart:convert';
import 'dart:io';
import 'package:sai_nodes_core/sai_nodes_core.dart';

import '../packages/sai_nodes/test/support/benchmark_graph.dart';

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
