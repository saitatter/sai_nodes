import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
      'node editor supports selection, primary-button panning, and a clean canvas',
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

      await tester.tapAt(const Offset(400, 300));
      await tester.pump();
      expect(controller.selectedNodeIds, hasLength(1));

      await tester.dragFrom(
        const Offset(650, 450),
        const Offset(80, 40),
        buttons: kPrimaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(controller.viewportOffset, const Offset(80, 40));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
