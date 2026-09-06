import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:sai_nodes/sai_nodes.dart';

NodePrototype _prototype(String id) => NodePrototype(
      idName: id,
      displayName: (_) => id,
      description: (_) => id,
      onExecute: (ports, fields, state, forward, put) async {},
    );

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NodeEditorController controller;

  setUp(() {
    controller = NodeEditorController(
      config: const NodeEditorConfig(
        enableSnapToGrid: false,
        autoBuildGraph: false,
        autoRunGraph: false,
      ),
    );
    controller.registerNodePrototype(_prototype('node'));
  });

  tearDown(() => controller.dispose());

  test('viewport transform round trips local screen and world coordinates', () {
    const transform = NodeEditorViewportTransform(
      viewportSize: Size(800, 600),
      viewportOffset: Offset(40, -25),
      zoom: 2,
    );

    const world = Offset(123, -45);
    expect(transform.screenToWorld(transform.worldToScreen(world)), world);
    expect(
      transform.visibleWorldBounds,
      const Rect.fromLTWH(-240, -125, 400, 300),
    );
  });

  test('navigation selects the nearest node in the requested direction', () {
    final current = controller.addNode('node', offset: Offset.zero);
    final near = controller.addNode('node', offset: const Offset(100, 10));
    controller.addNode('node', offset: const Offset(130, 90));
    controller.selectNodesById({current.id});

    expect(
      controller.navigateSelection(NodeNavigationDirection.right),
      near.id,
    );
    expect(controller.selectedNodeIds, {near.id});
  });

  test('content revision ignores selection and tracks persisted events',
      () async {
    final initial = controller.contentRevisionNotifier.value;
    final node = controller.addNode('node');
    await _flushEvents();
    expect(controller.contentRevisionNotifier.value, initial + 1);

    controller.selectNodesById({node.id});
    await _flushEvents();
    expect(controller.contentRevisionNotifier.value, initial + 1);

    controller.applyLayout({node.id: const Offset(80, 30)});
    await _flushEvents();
    expect(controller.contentRevisionNotifier.value, initial + 2);
  });

  test('layout is one undoable operation', () async {
    final first = controller.addNode('node', offset: const Offset(0, 10));
    final second = controller.addNode('node', offset: const Offset(100, 70));
    await _flushEvents();

    controller.applyLayout({
      first.id: const Offset(20, 30),
      second.id: const Offset(120, 90),
    });
    await _flushEvents();

    controller.history.undo();
    expect(controller.nodes[first.id]!.offset, const Offset(0, 10));
    expect(controller.nodes[second.id]!.offset, const Offset(100, 70));

    controller.history.redo();
    expect(controller.nodes[first.id]!.offset, const Offset(20, 30));
    expect(controller.nodes[second.id]!.offset, const Offset(120, 90));
  });

  test('clipboard extension data follows pasted nodes', () async {
    Map<String, dynamic>? decoded;
    Iterable<NodeDataModel>? pastedNodes;
    final extensionController = NodeEditorController(
      config: const NodeEditorConfig(
        enableSnapToGrid: false,
        autoBuildGraph: false,
        autoRunGraph: false,
      ),
      clipboardPayloadEncoder: (nodes) => {
        'types': nodes.map((node) => node.prototype.idName).toList(),
      },
      clipboardPayloadDecoder: (data, nodes) {
        decoded = data;
        pastedNodes = nodes;
      },
    );
    extensionController.registerNodePrototype(_prototype('node'));

    try {
      final node = extensionController.addNode('node');
      extensionController.selectNodesById({node.id});
      await _flushEvents();

      final payload = await extensionController.clipboard.copySelection();
      await extensionController.clipboard.pasteSelection(
        clipboardContent: payload,
        position: const Offset(100, 100),
      );
      await _flushEvents();

      expect(decoded, {
        'types': ['node'],
      });
      expect(pastedNodes, hasLength(1));
      expect(pastedNodes!.single.id, isNot(node.id));
    } finally {
      extensionController.dispose();
    }
  });
}
