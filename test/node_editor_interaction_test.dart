import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
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

  testWidgets(
      'node editor supports selection, node dragging, middle-button panning, and a clean canvas',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final controller = NodeEditorController(
        config: const NodeEditorConfig(
          autoBuildGraph: false,
          autoRunGraph: false,
          enableSnapToGrid: false,
        ),
      );
      addTearDown(controller.dispose);
      controller.registerNodePrototype(_prototype('node'));
      final node = controller.addNode('node');
      node.customSize = const Size(180, 100);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: NodeEditorWidget(
                controller: controller,
                shaderAssetKey: 'shaders/grid.frag',
                overlay: () => const <OverlayData>[],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Offset:'), findsNothing);
      expect(find.textContaining('Zoom:'), findsNothing);

      final nodeTitle = find.text('node');
      expect(nodeTitle, findsOneWidget);
      final editorBox =
          controller.editorKey.currentContext!.findRenderObject()! as RenderBox;
      final nodeBox = node.key.currentContext!.findRenderObject()! as RenderBox;
      final nodeCenter = editorBox.localToGlobal(
        controller.worldToScreen(
          node.offset + Offset(nodeBox.size.width / 2, nodeBox.size.height / 2),
          editorBox.size,
        ),
      );
      await tester.tapAt(nodeCenter);
      await tester.pump();
      expect(controller.selectedNodeIds, contains(node.id));

      final initialNodeOffset = node.offset;
      await tester.dragFrom(
        nodeCenter,
        const Offset(80, 40),
        buttons: kPrimaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(node.offset, isNot(initialNodeOffset));

      await tester.tapAt(const Offset(400, 300));
      await tester.pump();
      expect(controller.selectedNodeIds, isEmpty);

      await tester.tapAt(
        const Offset(650, 450),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      expect(find.text('EDITOR MENU'), findsOneWidget);
      expect(find.text('Center View'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      await tester.dragFrom(
        const Offset(650, 450),
        const Offset(80, 40),
        buttons: kMiddleMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(controller.viewportOffset, const Offset(80, 40));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('node hit testing uses the editor local coordinate space',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final controller = NodeEditorController(
        config: const NodeEditorConfig(
          autoBuildGraph: false,
          autoRunGraph: false,
          enableSnapToGrid: false,
        ),
      );
      addTearDown(controller.dispose);
      controller.registerNodePrototype(_prototype('node'));
      final node = controller.addNode('node');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 48, top: 32),
                child: SizedBox(
                  width: 720,
                  height: 500,
                  child: NodeEditorWidget(
                    controller: controller,
                    shaderAssetKey: 'shaders/grid.frag',
                    overlay: () => const <OverlayData>[],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final editorBox =
          controller.editorKey.currentContext!.findRenderObject()! as RenderBox;
      final nodeBox = node.key.currentContext!.findRenderObject()! as RenderBox;
      final nodeCenter = editorBox.localToGlobal(
        controller.worldToScreen(
          node.offset + Offset(nodeBox.size.width / 2, nodeBox.size.height / 2),
          editorBox.size,
        ),
      );

      await tester.tapAt(nodeCenter);
      await tester.pump();
      expect(controller.selectedNodeIds, contains(node.id));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
