import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:sai_nodes/sai_nodes.dart';

NodePrototype _flowPrototype() => NodePrototype(
      idName: 'flow',
      displayName: (_) => 'Flow',
      description: (_) => 'Flow',
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
    controller.registerNodePrototype(_flowPrototype());
  });

  tearDown(() => controller.dispose());

  test('splices a detached node atomically and preserves link metadata',
      () async {
    final source = controller.addNode('flow', offset: const Offset(0, 0));
    final target = controller.addNode('flow', offset: const Offset(300, 0));
    final original = controller.addLink(
      source.id,
      'out',
      target.id,
      'in',
      label: 'then',
    )!;
    controller.selectLinkById(original.id);
    await _flushEvents();

    final inserted = controller.createNodeModel(
      'flow',
      offset: const Offset(150, 0),
    );
    final result = controller.spliceNodeIntoLink(
      original.id,
      inserted,
      inputPortId: 'in',
      outputPortId: 'out',
    );
    await _flushEvents();

    expect(result?.id, inserted.id);
    expect(controller.links, hasLength(2));
    expect(controller.links.containsKey(original.id), isFalse);
    final incoming = controller.links.values.firstWhere(
      (link) => link.endpoints.targetNodeId == inserted.id,
    );
    final outgoing = controller.links.values.firstWhere(
      (link) => link.endpoints.sourceNodeId == inserted.id,
    );
    expect(incoming.label, 'then');
    expect(incoming.state.isSelected, isTrue);
    expect(outgoing.label, isNull);

    controller.history.undo();
    await _flushEvents();
    expect(controller.nodes.containsKey(inserted.id), isFalse);
    expect(controller.links, containsPair(original.id, original));
    expect(controller.links, hasLength(1));

    controller.history.redo();
    await _flushEvents();
    expect(controller.nodes.containsKey(inserted.id), isTrue);
    expect(controller.links, hasLength(2));
  });

  test('rejects an invalid splice without changing the graph', () async {
    final source = controller.addNode('flow');
    final target = controller.addNode('flow', offset: const Offset(200, 0));
    final original = controller.addLink(source.id, 'out', target.id, 'in')!;
    final beforeNodes = controller.nodes.length;
    final beforeLinks = controller.links.length;

    final result = controller.spliceNodeIntoLink(
      original.id,
      controller.createNodeModel('flow'),
      inputPortId: 'missing',
      outputPortId: 'out',
    );

    expect(result, isNull);
    expect(controller.nodes.length, beforeNodes);
    expect(controller.links.length, beforeLinks);
    expect(controller.links[original.id], same(original));
  });

  test('frame operations are atomic and undoable', () async {
    final first = controller.addNode('flow');
    final second = controller.addNode('flow', offset: const Offset(200, 0));
    await _flushEvents();

    final frame = controller.createFrame(
      title: '  Main path  ',
      bounds: const Rect.fromLTWH(0, 0, 400, 200),
      members: [first.id, 'missing'],
      id: 'main-frame',
    );
    await _flushEvents();
    expect(frame.title, 'Main path');
    expect(controller.frames['main-frame']!.members, {first.id});

    controller.addNodesToFrame('main-frame', [second.id]);
    controller.moveFrame('main-frame', const Offset(10, 20));
    controller.resizeFrame(
      'main-frame',
      const Offset(-500, -500),
      minimumSize: const Size(120, 80),
    );
    await _flushEvents();
    expect(controller.frames['main-frame']!.members, {first.id, second.id});
    expect(controller.frames['main-frame']!.bounds.size, const Size(120, 80));

    controller.removeNodesFromFrame('main-frame', [first.id]);
    await _flushEvents();
    expect(controller.frames['main-frame']!.members, {second.id});

    controller.history.undo();
    await _flushEvents();
    expect(controller.frames['main-frame']!.members, {first.id, second.id});

    controller.history.undo();
    await _flushEvents();
    expect(controller.frames['main-frame']!.bounds.size, const Size(400, 200));

    controller.history.undo();
    await _flushEvents();
    expect(controller.frames['main-frame']!.bounds.topLeft, Offset.zero);

    controller.history.undo();
    await _flushEvents();
    controller.history.undo();
    await _flushEvents();
    expect(controller.frames['main-frame'], isNull);
  });
}
