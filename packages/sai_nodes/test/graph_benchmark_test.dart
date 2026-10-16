import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';
import '../../../benchmark/core_benchmark.dart'
    show benchmarkDocument, benchmarkDefinitions, summary;

void main() {
  testWidgets(
    'measure scene, visible mounting, pan, zoom, drag, hit testing and minimap',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final report = <String, Object?>{};
      for (final count in [100, 500, 1000, 3000, 5000]) {
        final measurements = <String, List<double>>{};
        for (var sample = 0; sample < 5; sample++) {
          final graph = GraphController(
            document: benchmarkDocument(count),
            resolver: GraphResolver(
              definitions: benchmarkDefinitions(),
              types: GraphTypeSystem.core(),
            ),
          );
          final clock = Stopwatch()..start();
          final scene = GraphSceneBuilder().build(graph);
          clock.stop();
          (measurements['scene_build'] ??= []).add(
            clock.elapsedMicroseconds / 1000,
          );
          Future<void> measure(
            String name,
            Future<void> Function() operation,
          ) async {
            final timer = Stopwatch()..start();
            await operation();
            timer.stop();
            (measurements[name] ??= []).add(timer.elapsedMicroseconds / 1000);
          }

          Widget app({bool minimap = false}) => MaterialApp(
            home: Scaffold(
              body: NodeEditor(controller: graph, showMinimap: minimap),
            ),
          );
          await measure('initial_render', () => tester.pumpWidget(app()));
          expect(find.byKey(ValueKey('node:n${count - 1}')), findsNothing);
          await measure('pan_frame', () async {
            graph.setCamera(graph.camera.pan(const GraphPoint(-100, -50)));
            await tester.pump();
          });
          await measure('zoom_frame', () async {
            graph.setCamera(
              graph.camera.zoomAt(const GraphPoint(600, 400), 1.2),
            );
            await tester.pump();
          });
          await measure('node_drag_update', () async {
            graph.execute(
              MoveNodesCommand('main', {'n0': const GraphPoint(40, 50)}),
            );
            await tester.pump();
          });
          clock.reset();
          clock.start();
          for (var hit = 0; hit < 100; hit++) {
            scene.hitConnection(
              GraphPoint((hit % 10) * 320 + 280, (hit ~/ 10) * 180 + 50),
            );
          }
          clock.stop();
          (measurements['connection_hit_100'] ??= []).add(
            clock.elapsedMicroseconds / 1000,
          );
          await measure(
            'minimap_render',
            () => tester.pumpWidget(app(minimap: true)),
          );
          await tester.pumpWidget(const SizedBox());
          graph.dispose();
        }
        report['$count'] = {
          for (final entry in measurements.entries)
            entry.key: summary(entry.value),
        };
      }
      final folder = Directory('../../.tmp/benchmarks')
        ..createSync(recursive: true);
      File('${folder.path}/flutter.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'samples': 5,
          'measurement':
              'widget-test wall-clock milliseconds, not production GPU frame timings',
          'milliseconds': report,
        }),
      );
    },
    skip: Platform.environment['SAI_NODES_BENCHMARK'] != '1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
