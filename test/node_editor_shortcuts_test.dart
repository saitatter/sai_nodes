import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';

void main() {
  testWidgets('default arrows navigate and Shift extends selection',
      (tester) async {
    final controller = NodeEditorController(
      config: const NodeEditorConfig(
        autoBuildGraph: false,
        autoRunGraph: false,
      ),
    );
    addTearDown(controller.dispose);
    controller.registerNodePrototype(
      NodePrototype(
        idName: 'node',
        displayName: (_) => 'Node',
        description: (_) => '',
        onExecute: (ports, fields, state, forward, put) async {},
      ),
    );
    final first = controller.addNode('node');
    final second = controller.addNode('node', offset: const Offset(150, 0));
    final third = controller.addNode('node', offset: const Offset(300, 0));
    controller.selectNodesById({first.id});
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: NodeEditorShortcutsWidget(
            controller: controller,
            child: NodeEditorWidget(
              controller: controller,
              shaderAssetKey: 'shaders/grid.frag',
              overlay: () => [],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(controller.selectedNodeIds, {second.id});
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(controller.selectedNodeIds, {second.id, third.id});
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(controller.viewportZoom, closeTo(0.9, 0.001));
  });
}
