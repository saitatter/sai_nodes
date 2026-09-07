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
        home: Scaffold(
          body: Column(
            children: [
              NodeEditorToolbar(controller: controller),
              Expanded(
                child: NodeEditorWidget(
                  controller: controller,
                  shaderAssetKey: 'shaders/grid.frag',
                  overlay: () => [],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Select all nodes'));
    await tester.pump();
    expect(controller.selectedNodeIds, hasLength(1));

    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    expect(find.text('90%'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete selection'));
    expect(controller.nodes, isEmpty);
  });
}
