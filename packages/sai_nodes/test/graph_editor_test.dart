import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';

GraphController fixture({bool far = false}) {
  final registry = NodeDefinitionRegistry();
  registry.register(
    DeclarativeNodeDefinition(
      type: 'number',
      displayName: 'Number',
      ports: [
        StaticPortFamily([
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
        ]),
      ],
      fields: [
        StaticFieldFamily([
          ResolvedField(
            id: 'value',
            label: 'Value',
            kind: GraphFieldKind.number,
          ),
        ]),
      ],
    ),
  );
  return GraphController(
    document: GraphDocument(
      id: 'd',
      spaces: {
        'main': GraphSpace(
          id: 'main',
          nodes: {
            'a': GraphNode(id: 'a', type: 'number', data: {'value': 1}),
            'b': GraphNode(id: 'b', type: 'number', data: {'value': 2}),
          },
          nodePresentations: {
            'a': NodePresentation(
              nodeId: 'a',
              position: const GraphPoint(50, 60),
            ),
            'b': NodePresentation(
              nodeId: 'b',
              position: GraphPoint(far ? 20000 : 450, 60),
            ),
          },
        ),
      },
    ),
    resolver: GraphResolver(
      definitions: registry,
      types: GraphTypeSystem.core(),
    ),
  );
}

Future<void> mount(
  WidgetTester tester,
  GraphController graph, {
  GraphExecutionVisualSource? source,
  GraphNodeWidgetBuilder? builder,
  Future<GraphNode?> Function(GraphNodePickerRequest)? picker,
  bool minimap = false,
}) async {
  if (!tester.testTextInput.isRegistered) {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
  }
  await tester.binding.setSurfaceSize(const Size(900, 650));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NodeEditor(
          controller: graph,
          showMinimap: minimap,
          executionSource: source,
          nodeBuilder: builder,
          onCreateNode: picker,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'edge auto-scroll keeps a node drag active and coalesces its history',
    (tester) async {
      final graph = fixture();
      addTearDown(graph.dispose);
      await mount(tester, graph);
      final drag = await tester.startGesture(const Offset(80, 75));
      await drag.moveTo(const Offset(885, 80));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      expect(graph.camera.offset.x, lessThan(0));
      expect(graph.undoCount, 1);
      await drag.up();
      await tester.pumpAndSettle();
      graph.undo();
      expect(
        graph.activeSpace!.nodePresentations['a']!.position,
        const GraphPoint(50, 60),
      );
    },
  );
  testWidgets(
    'node resizing and frame/comment dragging use transactional geometry',
    (tester) async {
      final graph = fixture();
      addTearDown(graph.dispose);
      await mount(tester, graph);
      final node = tester.getRect(find.byKey(const ValueKey('node:a')));
      await tester.dragFrom(
        node.bottomRight - const Offset(4, 4),
        const Offset(40, 30),
      );
      await tester.pumpAndSettle();
      expect(graph.activeSpace!.nodePresentations['a']!.size!.width, 300);
      graph.selectAll();
      final scene = GraphSceneBuilder().build(graph);
      final bounds = scene.nodes.values
          .map((node) => node.geometry.bounds)
          .reduce((a, b) => a.union(b))
          .inflate(24);
      graph.createFrameFromSelection(bounds, idFactory: () => 'frame');
      await tester.pump();
      await tester.dragFrom(
        Offset(bounds.left + 10, bounds.top + 10),
        const Offset(20, 30),
      );
      await tester.pumpAndSettle();
      expect(
        graph.activeSpace!.nodePresentations['a']!.position,
        const GraphPoint(70, 90),
      );
      graph.execute(
        CreateCommentCommand(
          'main',
          GraphComment(
            id: 'note',
            bounds: const GraphRect(500, 350, 200, 100),
            text: 'Note',
          ),
        ),
      );
      await tester.pump();
      await tester.dragFrom(const Offset(520, 365), const Offset(30, 40));
      await tester.pumpAndSettle();
      expect(
        graph.activeSpace!.comments['note']!.bounds,
        const GraphRect(530, 390, 200, 100),
      );
      graph.undo();
      expect(
        graph.activeSpace!.comments['note']!.bounds,
        const GraphRect(500, 350, 200, 100),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reconnect preserves connection identity and waypoint dragging is undoable',
    (tester) async {
      final graph = fixture();
      addTearDown(graph.dispose);
      await mount(tester, graph);
      graph.execute(
        AddConnectionCommand(
          'main',
          GraphConnection(
            id: 'stable',
            from: const PortRef(nodeId: 'a', portId: 'value.out'),
            to: const PortRef(nodeId: 'b', portId: 'value.in'),
            kind: GraphConnectionKind.data,
          ),
        ),
      );
      await tester.pump();
      final from = tester.getCenter(
            find.byKey(const ValueKey('port:b:value.in')),
          ),
          to = tester.getCenter(find.byKey(const ValueKey('port:a:value.in')));
      await tester.dragFrom(from, to - from);
      await tester.pumpAndSettle();
      expect(graph.activeSpace!.connections.keys, ['stable']);
      expect(graph.activeSpace!.connections['stable']!.to.nodeId, 'a');
      graph.undo();
      graph.execute(
        UpdateConnectionPresentationCommand(
          'main',
          ConnectionPresentation(
            connectionId: 'stable',
            waypoints: [const GraphPoint(380, 220)],
          ),
        ),
      );
      graph.select(GraphSelection(connections: {'stable'}));
      await tester.pump();
      await tester.dragFrom(const Offset(380, 220), const Offset(20, 40));
      await tester.pumpAndSettle();
      expect(graph.activeSpace!.connectionPresentations['stable']!.waypoints, [
        const GraphPoint(400, 260),
      ]);
      graph.undo();
      expect(graph.activeSpace!.connectionPresentations['stable']!.waypoints, [
        const GraphPoint(380, 220),
      ]);
    },
  );
  testWidgets(
    'create connection by dragging ports, move node and undo deletion',
    (tester) async {
      final graph = fixture();
      addTearDown(graph.dispose);
      await mount(tester, graph);
      final source = tester.getCenter(
            find.byKey(const ValueKey('port:a:value.out')),
          ),
          target = tester.getCenter(
            find.byKey(const ValueKey('port:b:value.in')),
          );
      await tester.dragFrom(source, target - source);
      await tester.pumpAndSettle();
      expect(graph.activeSpace!.connections.length, 1);
      expect(graph.resolution.diagnostics, isEmpty);
      final header =
          tester.getTopLeft(find.byKey(const ValueKey('node:a'))) +
          const Offset(30, 15);
      await tester.dragFrom(header, const Offset(45, 55));
      await tester.pumpAndSettle();
      expect(
        graph.activeSpace!.nodePresentations['a']!.position,
        const GraphPoint(95, 115),
      );
      final before = graph.document;
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(graph.activeSpace!.nodes.keys, ['b']);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(graph.document, before);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'typed fields retain focus and graph shortcuts do not delete text-editing nodes',
    (tester) async {
      final graph = fixture();
      addTearDown(graph.dispose);
      await mount(tester, graph);
      final field = find.descendant(
        of: find.byKey(const ValueKey('node:a')),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, '42');
      await tester.pump();
      expect(graph.activeSpace!.nodes['a']!.data['value'], 42);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(graph.activeSpace!.nodes.length, 2);
      expect(FocusManager.instance.primaryFocus?.hasFocus, true);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'viewport virtualization keeps focused field alive when panning away',
    (tester) async {
      final graph = fixture(far: true);
      addTearDown(graph.dispose);
      await mount(tester, graph);
      expect(find.byKey(const ValueKey('node:a')), findsOneWidget);
      expect(find.byKey(const ValueKey('node:b')), findsNothing);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      graph.setCamera(const GraphCamera(offset: GraphPoint(-20000, 0)));
      await tester.pump();
      expect(find.byKey(const ValueKey('node:a')), findsOneWidget);
      expect(find.byKey(const ValueKey('node:b')), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.hasFocus, true);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      graph.setCamera(const GraphCamera(offset: GraphPoint(-20001, 0)));
      await tester.pump();
      expect(find.byKey(const ValueKey('node:a')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'execution snapshots repaint without rebuilding node contents or dirtying graph',
    (tester) async {
      final graph = fixture();
      addTearDown(graph.dispose);
      final visuals = GraphExecutionVisualController();
      addTearDown(visuals.dispose);
      var builds = 0;
      await mount(
        tester,
        graph,
        source: visuals,
        builder: (context, node) {
          builds++;
          return ColoredBox(color: Colors.grey, child: Text(node.label));
        },
      );
      final baseline = builds;
      visuals.apply(
        GraphExecutionSnapshot(
          executionId: 'run',
          nodes: {
            const ScopedNodeRef('main', 'a'): NodeExecutionVisual(
              status: GraphExecutionStatus.running,
              activeCount: 2,
              invocationCount: 3,
            ),
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(builds, baseline);
      expect(graph.isDirty, false);
      visuals.apply(
        GraphExecutionSnapshot(
          nodes: {
            const ScopedNodeRef('main', 'a'): NodeExecutionVisual(
              status: GraphExecutionStatus.completed,
              invocationCount: 3,
              duration: const Duration(milliseconds: 25),
            ),
          },
        ),
      );
      await tester.pump();
      expect(builds, baseline);
      expect(graph.document.toJson().containsKey('execution'), false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'drop-to-create connects a compatible node in one history entry',
    (tester) async {
      final graph = fixture();
      addTearDown(graph.dispose);
      await mount(
        tester,
        graph,
        picker: (request) async =>
            GraphNode(id: 'created', type: 'number', data: {'value': 3}),
      );
      final start = tester.getCenter(
        find.byKey(const ValueKey('port:a:value.out')),
      );
      await tester.dragFrom(start, const Offset(80, 200));
      await tester.pumpAndSettle();
      expect(graph.activeSpace!.nodes.length, 3);
      expect(graph.activeSpace!.connections.length, 1);
      expect(graph.undoCount, 1);
      graph.undo();
      await tester.pump();
      expect(graph.activeSpace!.nodes.length, 2);
      expect(graph.activeSpace!.connections, isEmpty);
    },
  );
  testWidgets(
    'marquee selects nodes and minimap interaction stays outside canvas gestures',
    (tester) async {
      final graph = fixture();
      addTearDown(graph.dispose);
      await mount(tester, graph, minimap: true);
      await tester.dragFrom(const Offset(20, 20), const Offset(730, 220));
      await tester.pumpAndSettle();
      expect(graph.selection.nodes, {'a', 'b'});
      final revision = graph.revision;
      await tester.tap(find.text('Hide minimap'));
      await tester.pumpAndSettle();
      expect(graph.selection.nodes, {'a', 'b'});
      expect(graph.revision, revision);
      expect(find.text('Show minimap'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'context comment editing and connection waypoint undo are functional',
    (tester) async {
      final graph = fixture();
      addTearDown(graph.dispose);
      await mount(tester, graph);
      graph.execute(
        AddConnectionCommand(
          'main',
          GraphConnection(
            id: 'e',
            from: const PortRef(nodeId: 'a', portId: 'value.out'),
            to: const PortRef(nodeId: 'b', portId: 'value.in'),
            kind: GraphConnectionKind.data,
          ),
        ),
      );
      await tester.pump();
      const midpoint = Offset(380, 112);
      await tester.tapAt(midpoint);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(midpoint);
      await tester.pumpAndSettle();
      expect(
        graph.activeSpace!.connectionPresentations['e']!.waypoints.length,
        1,
      );
      graph.undo();
      await tester.pump();
      expect(graph.activeSpace!.connectionPresentations, isEmpty);
      await tester.tapAt(
        const Offset(450, 350),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add comment'));
      await tester.pumpAndSettle();
      expect(graph.activeSpace!.comments.length, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'wheel zoom preserves pointer anchor and touch pinch remains ephemeral',
    (tester) async {
      final graph = fixture();
      addTearDown(graph.dispose);
      await mount(tester, graph);
      const anchor = GraphPoint(350, 250);
      final world = graph.camera.viewportToWorld(anchor);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(350, 250),
          scrollDelta: Offset(0, -100),
        ),
      );
      await tester.pump();
      expect(
        graph.camera.viewportToWorld(anchor).distanceTo(world),
        lessThan(.00001),
      );
      expect(graph.isDirty, false);
      final first = await tester.startGesture(
        const Offset(300, 300),
        pointer: 1,
      );
      final second = await tester.startGesture(
        const Offset(500, 300),
        pointer: 2,
      );
      final before = graph.camera.zoom;
      await second.moveTo(const Offset(600, 300));
      await tester.pump();
      expect(graph.camera.zoom, greaterThan(before));
      await first.up();
      await second.up();
      expect(graph.isDirty, false);
      expect(tester.takeException(), isNull);
    },
  );
}
