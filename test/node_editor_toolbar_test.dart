import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';

NodePrototype _prototype(String id) => NodePrototype(
      idName: id,
      displayName: (_) => id,
      description: (_) => id,
      onExecute: (ports, fields, state, forward, put) async {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('toolbar exposes selection and reset actions', (tester) async {
    final controller = NodeEditorController(
      config: const NodeEditorConfig(
        autoBuildGraph: false,
        autoRunGraph: false,
      ),
    );
    addTearDown(controller.dispose);
    controller.registerNodePrototype(_prototype('node'));
    controller.addNode('node');

    await tester.pumpWidget(
      MaterialApp(
        home: NodeEditorToolbar(controller: controller),
      ),
    );

    await tester.tap(find.byTooltip('Select all nodes'));
    await tester.pump();
    expect(controller.selectedNodeIds, hasLength(1));

    await tester.tap(find.byTooltip('Delete selection'));
    expect(controller.nodes, isEmpty);
  });
}
