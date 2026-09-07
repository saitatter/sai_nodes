import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';

void main() {
  testWidgets(
      'selection pixels stay at pointer coordinates across child layers',
      (tester) async {
    final controller = NodeEditorController(
      config:
          const NodeEditorConfig(autoBuildGraph: false, autoRunGraph: false),
      style: const NodeEditorStyle(
        highlightAreaStyle: HighlightAreaStyle(
          color: Color(0xffff00ff),
          borderColor: Color(0xffff00ff),
          borderWidth: 1,
          borderDrawMode: LineDrawMode.solid,
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.registerNodePrototype(
      NodePrototype(
        idName: 'node',
        displayName: (_) => 'node',
        description: (_) => '',
        onExecute: (ports, fields, state, forward, put) async {},
      ),
    );
    final node = controller.addNode('node');
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: RepaintBoundary(
          key: captureKey,
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(160, 100, 40, 40),
              child: NodeEditorWidget(
                controller: controller,
                shaderAssetKey: 'shaders/grid.frag',
                overlay: () => [],
                headerBuilder: (context, node, style, collapse) =>
                    const RepaintBoundary(
                  child: SizedBox(width: 120, height: 40),
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
    for (final zoom in [1.0, 0.65, 1.4]) {
      controller.setViewportZoom(zoom, animate: false);
      controller.setViewportOffset(
        const Offset(45, -25),
        absolute: true,
        animate: false,
      );
      await tester.pumpAndSettle();
      const localRect = Rect.fromLTWH(30, 30, 110, 70);
      final gesture = await tester.startGesture(
        editorBox.localToGlobal(localRect.topLeft),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(editorBox.localToGlobal(localRect.bottomRight));
      await tester.pumpAndSettle();
      final boundary = captureKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = (await tester.runAsync(() => boundary.toImage()))!;
      final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      final expected = editorBox.localToGlobal(localRect.center);
      final pixel =
          (expected.dy.toInt() * image.width + expected.dx.toInt()) * 4;
      expect(bytes.getUint8(pixel), 255, reason: 'red at zoom $zoom');
      expect(bytes.getUint8(pixel + 1), 0, reason: 'green at zoom $zoom');
      expect(bytes.getUint8(pixel + 2), 255, reason: 'blue at zoom $zoom');
      final outside = (80 * image.width + 100) * 4;
      expect(
        bytes.getUint8(outside + 1),
        255,
        reason: 'selection must not paint over surrounding UI',
      );
      image.dispose();
      await gesture.up();
      await tester.pumpAndSettle();
      final nodeBox = node.key.currentContext!.findRenderObject()! as RenderBox;
      final expectedNodeOrigin = editorBox.localToGlobal(
        controller.worldToScreen(node.offset, editorBox.size),
      );
      expect(
        (nodeBox.localToGlobal(Offset.zero) - expectedNodeOrigin).distance,
        lessThan(0.01),
      );
      await tester.tapAt(nodeBox.localToGlobal(const Offset(40, 20)));
      await tester.pumpAndSettle();
      expect(controller.selectedNodeIds, contains(node.id));
    }
  });
}
