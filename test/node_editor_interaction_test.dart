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
      final events = <NodeEditorEvent>[];
      final eventSubscription = controller.eventBus.events.listen(events.add);
      addTearDown(eventSubscription.cancel);

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
      expect(events.whereType<DragSelectionStartEvent>(), hasLength(1));
      expect(events.whereType<DragSelectionEvent>(), isNotEmpty);
      expect(events.whereType<DragSelectionEndEvent>(), hasLength(1));

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

  testWidgets('node double tap delegates to the host application',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final controller = NodeEditorController(
        config: const NodeEditorConfig(
          autoBuildGraph: false,
          autoRunGraph: false,
        ),
      );
      addTearDown(controller.dispose);
      controller.registerNodePrototype(_prototype('node'));
      final node = controller.addNode('node');
      node.customSize = const Size(180, 100);

      NodeDataModel? doubleTapped;
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
                onNodeDoubleTap: (_, tappedNode) => doubleTapped = tappedNode,
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
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(nodeCenter);
      await tester.pump(const Duration(milliseconds: 500));

      expect(doubleTapped?.id, node.id);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('custom port builders preserve endpoint layout keys',
      (tester) async {
    final controller = NodeEditorController(
      config: const NodeEditorConfig(
        autoBuildGraph: false,
        autoRunGraph: false,
        enableSnapToGrid: false,
      ),
    );
    addTearDown(controller.dispose);
    controller.registerNodePrototype(
      NodePrototype(
        idName: 'ports',
        displayName: (_) => 'ports',
        description: (_) => 'ports',
        ports: [
          ControlInputPortPrototype(
            idName: 'in',
            displayName: (_) => 'In',
            styleBuilder: defaultPortStyleBuilder,
          ),
          ControlOutputPortPrototype(
            idName: 'out',
            displayName: (_) => 'Out',
            styleBuilder: defaultPortStyleBuilder,
          ),
        ],
        onExecute: (ports, fields, state, forward, put) async {},
      ),
    );
    final node = controller.addNode('ports');

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
              portBuilder: (context, port, style) => Text(
                key: port.key,
                port.prototype.displayName(context),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      node.ports['in']!.key.currentContext?.findRenderObject(),
      isA<RenderBox>(),
    );
    expect(
      node.ports['out']!.key.currentContext?.findRenderObject(),
      isA<RenderBox>(),
    );
    expect(node.ports['in']!.offset.dy, greaterThan(0));
    expect(node.ports['out']!.offset.dx, greaterThan(0));
  });

  testWidgets('dragging an existing link reconnects it to another port',
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
      controller.registerNodePrototype(
        NodePrototype(
          idName: 'flow',
          displayName: (_) => 'flow',
          description: (_) => 'flow',
          ports: [
            ControlInputPortPrototype(
              idName: 'in',
              displayName: (_) => 'In',
              styleBuilder: defaultPortStyleBuilder,
            ),
            ControlOutputPortPrototype(
              idName: 'out',
              displayName: (_) => 'Out',
              styleBuilder: defaultPortStyleBuilder,
            ),
          ],
          onExecute: (ports, fields, state, forward, put) async {},
        ),
      );
      final source = controller.addNode(
        'flow',
        offset: const Offset(-240, -40),
        snapToGrid: false,
      )..customSize = const Size(120, 100);
      final oldTarget = controller.addNode(
        'flow',
        offset: const Offset(40, -40),
        snapToGrid: false,
      )..customSize = const Size(120, 100);
      final newTarget = controller.addNode(
        'flow',
        offset: const Offset(40, 180),
        snapToGrid: false,
      )..customSize = const Size(120, 100);
      controller.addLink(source.id, 'out', oldTarget.id, 'in');

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
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

      final editorBox =
          controller.editorKey.currentContext!.findRenderObject()! as RenderBox;
      final link = controller.linksAsList.single;
      final start = source.offset + source.ports['out']!.offset;
      final end = oldTarget.offset + oldTarget.ports['in']!.offset;
      final linkPoint = editorBox.localToGlobal(
        controller.worldToScreen(
          Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2),
          editorBox.size,
        ),
      );
      final targetPoint = editorBox.localToGlobal(
        controller.worldToScreen(
          newTarget.offset + newTarget.ports['in']!.offset,
          editorBox.size,
        ),
      );

      final gesture = await tester.startGesture(
        linkPoint,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(targetPoint);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(controller.linksAsList, hasLength(1));
      expect(controller.linksAsList.single.id, isNot(link.id));
      expect(
        controller.linksAsList.single.endpoints.targetNodeId,
        newTarget.id,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('clips canvas projections to the editor bounds', (tester) async {
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
          body: SizedBox(
            width: 420,
            height: 300,
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

    final editorStacks = tester
        .widgetList<Stack>(
          find.descendant(
            of: find.byType(NodeEditorWidget),
            matching: find.byType(Stack),
          ),
        )
        .toList();
    expect(
      editorStacks.any((stack) => stack.clipBehavior == Clip.hardEdge),
      isTrue,
    );
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

  testWidgets('node context menus remain open after a secondary click',
      (tester) async {
    // The widget tree's platform is the source of truth for interaction
    // mode. Keep the process-wide default different to catch regressions
    // where nodes accidentally choose mobile gestures on a desktop canvas.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
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
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: NodeEditorWidget(
                controller: controller,
                shaderAssetKey: 'shaders/grid.frag',
                overlay: () => const <OverlayData>[],
                nodeMenuBuilder: (context, node) => [
                  NodeEditorMenuAction(
                    label: 'Node menu action',
                    onSelected: () {},
                  ),
                ],
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

      await tester.tapAt(nodeCenter, buttons: kSecondaryMouseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Node menu action'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('area selection follows the pointer in a padded editor',
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
      controller.addNode('node');

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
      const startLocal = Offset(24, 24);
      const endLocal = Offset(180, 148);
      final start = editorBox.localToGlobal(startLocal);
      final end = editorBox.localToGlobal(endLocal);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(end);
      await tester.pump();

      final expected = Rect.fromPoints(
        controller.screenToWorld(startLocal, editorBox.size),
        controller.screenToWorld(endLocal, editorBox.size),
      );
      expect(controller.highlightArea, expected);

      await gesture.up();
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
