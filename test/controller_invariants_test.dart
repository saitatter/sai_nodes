import 'dart:ui' show Offset, Rect, Size;

import 'package:sai_nodes/sai_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

NodePrototype _prototype({
  required String id,
  required bool input,
  required bool output,
}) =>
    NodePrototype(
      idName: id,
      displayName: (_) => id,
      description: (_) => id,
      ports: [
        if (input)
          ControlInputPortPrototype(
            idName: 'in',
            displayName: (_) => 'Input',
            styleBuilder: defaultPortStyleBuilder,
          ),
        if (output)
          ControlOutputPortPrototype(
            idName: 'out',
            displayName: (_) => 'Output',
            styleBuilder: defaultPortStyleBuilder,
          ),
      ],
      onExecute: (ports, fields, state, forward, put) async {},
    );

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
    controller.registerNodePrototype(
      _prototype(id: 'source', input: false, output: true),
    );
    controller.registerNodePrototype(
      _prototype(id: 'target', input: true, output: false),
    );
  });

  tearDown(() => controller.dispose());

  test('clear removes project data and transient editor state', () {
    final source = controller.addNode('source');
    final target = controller.addNode('target');
    final link = controller.addLink(source.id, 'out', target.id, 'in');

    controller.selectNodesById({source.id});
    if (link != null) controller.selectLinkById(link.id, holdSelection: true);
    controller.setHighlightArea(
      Rect.fromPoints(Offset.zero, const Offset(10, 10)),
    );

    controller.clear();

    expect(controller.nodes, isEmpty);
    expect(controller.links, isEmpty);
    expect(controller.selectedNodeIds, isEmpty);
    expect(controller.selectedLinkIds, isEmpty);
    expect(controller.highlightArea, isNull);
    expect(controller.tempLink, isNull);
  });

  test('invalid links are rejected without throwing', () {
    expect(
      () => controller.addLink('missing', 'out', 'also-missing', 'in'),
      returnsNormally,
    );
    expect(controller.links, isEmpty);
  });

  test('existing links cannot be inserted twice', () {
    final source = controller.addNode('source');
    final target = controller.addNode('target');
    final link = controller.addLink(source.id, 'out', target.id, 'in');

    expect(link, isNotNull);
    expect(link!.fromTo.sourceNodeId, source.id);
    expect(link.fromTo.sourcePortId, 'out');
    expect(link.fromTo.targetNodeId, target.id);
    expect(link.fromTo.targetPortId, 'in');
    controller.addLinkFromExisting(link);

    expect(controller.links, hasLength(1));
    expect(source.ports['out']!.links, hasLength(1));
    expect(target.ports['in']!.links, hasLength(1));
  });

  test('existing links use active nodes instead of project snapshots', () {
    final source = controller.addNode('source');
    final target = controller.addNode('target');
    final link = LinkDataModel(
      id: 'restored-link',
      fromTo: (
        from: source.id,
        to: 'out',
        fromPort: target.id,
        toPort: 'in',
      ),
      state: LinkState(),
    );

    controller.addLinkFromExisting(link);

    expect(controller.links[link.id], same(link));
    expect(source.ports['out']!.links, contains(link));
    expect(target.ports['in']!.links, contains(link));
  });

  test('existing links cannot duplicate an existing endpoint pair', () {
    final source = controller.addNode('source');
    final target = controller.addNode('target');
    final link = controller.addLink(source.id, 'out', target.id, 'in')!;
    final duplicate = LinkDataModel(
      id: 'different-id',
      fromTo: link.fromTo,
      state: LinkState(),
    );

    controller.addLinkFromExisting(duplicate);

    expect(controller.links, hasLength(1));
  });

  test('selection ignores IDs that are not in the current project', () {
    final source = controller.addNode('source');

    controller.selectNodesById({source.id, 'deleted-node'});

    expect(controller.selectedNodeIds, {source.id});
  });

  test('config copyWith preserves and updates every setting', () {
    const original = NodeEditorConfig(
      autoSave: true,
      autoBuildGraph: false,
      autoRunGraph: false,
      autoSaveInterval: Duration(seconds: 11),
      manualSaveDebounce: Duration(seconds: 12),
      autoBuildGraphDelay: Duration(seconds: 13),
      autoRunGraphDelay: Duration(seconds: 14),
      minNodeWidth: 20,
      minNodeHeight: 30,
      maxNodeWidth: 400,
      maxNodeHeight: 500,
      linkHitTestTolerance: 6,
      portHitTestTolerance: 7,
      enableNodeResize: true,
    );

    final copy = original.copyWith(
      autoSave: false,
      autoBuildGraph: true,
      autoRunGraph: true,
      autoSaveInterval: const Duration(seconds: 21),
      manualSaveDebounce: const Duration(seconds: 22),
      autoBuildGraphDelay: const Duration(seconds: 23),
      autoRunGraphDelay: const Duration(seconds: 24),
      minNodeWidth: 40,
      minNodeHeight: 50,
      maxNodeWidth: 600,
      maxNodeHeight: 700,
      linkHitTestTolerance: 8,
      portHitTestTolerance: 9,
      enableNodeResize: false,
    );

    expect(copy.autoSave, isFalse);
    expect(copy.autoBuildGraph, isTrue);
    expect(copy.autoRunGraph, isTrue);
    expect(copy.autoSaveInterval, const Duration(seconds: 21));
    expect(copy.manualSaveDebounce, const Duration(seconds: 22));
    expect(copy.autoBuildGraphDelay, const Duration(seconds: 23));
    expect(copy.autoRunGraphDelay, const Duration(seconds: 24));
    expect(copy.minNodeWidth, 40);
    expect(copy.minNodeHeight, 50);
    expect(copy.maxNodeWidth, 600);
    expect(copy.maxNodeHeight, 700);
    expect(copy.linkHitTestTolerance, 8);
    expect(copy.portHitTestTolerance, 9);
    expect(copy.enableNodeResize, isFalse);
  });

  test('config rejects invalid size and hit-test bounds', () {
    expect(
      () => NodeEditorConfig(minNodeWidth: 0),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => NodeEditorConfig(
        minNodeWidth: 200,
        maxNodeWidth: 100,
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => NodeEditorConfig(portHitTestTolerance: -1),
      throwsA(isA<AssertionError>()),
    );
  });

  test('node state accepts partial persisted JSON', () {
    final state = NodeState.fromJson({});

    expect(state.isSelected, isFalse);
    expect(state.isCollapsed, isFalse);
    expect(state.isHovered, isFalse);
  });

  test('node title is normalized, serialized, and undoable', () async {
    final source = controller.addNode('source');

    controller.renameNode(source.id, '  Custom source  ');

    expect(controller.nodes[source.id]!.customTitle, 'Custom source');
    expect(
      controller.nodes[source.id]!.toJson({})['customTitle'],
      'Custom source',
    );

    await Future<void>.delayed(Duration.zero);
    controller.history.undo();
    expect(controller.nodes[source.id]!.customTitle, isNull);

    controller.history.redo();
    expect(controller.nodes[source.id]!.customTitle, 'Custom source');
  });

  test('node size is clamped, serialized, and undoable', () async {
    final source = controller.addNode('source');

    controller.resizeNode(source.id, const Size(10, 2000));
    controller.resizeNode(source.id, const Size(100, 200));

    expect(
      controller.nodes[source.id]!.customSize,
      const Size(100, 200),
    );
    expect(
      controller.nodes[source.id]!.toJson({})['size'],
      [100.0, 200.0],
    );

    await Future<void>.delayed(Duration.zero);
    controller.history.undo();
    expect(controller.nodes[source.id]!.customSize, isNull);

    controller.history.redo();
    expect(controller.nodes[source.id]!.customSize, const Size(100, 200));
  });

  test('deleting entities removes stale selections', () {
    final source = controller.addNode('source');
    final target = controller.addNode('target');
    final link = controller.addLink(source.id, 'out', target.id, 'in')!;

    controller.selectNodesById({source.id});
    controller.selectLinkById(link.id, holdSelection: true);
    controller.removeLinkById(link.id);
    controller.removeNodeById(source.id);

    expect(controller.selectedLinkIds, isEmpty);
    expect(controller.selectedNodeIds, isEmpty);
  });

  test('selection actions operate on the current project', () {
    final source = controller.addNode('source');
    final target = controller.addNode('target');

    controller.selectAllNodes();
    expect(controller.selectedNodeIds, {source.id, target.id});

    controller.invertNodeSelection();
    expect(controller.selectedNodeIds, isEmpty);

    controller.selectNodesById({source.id});
    controller.deleteSelection();

    expect(controller.nodes.keys, {target.id});
    expect(controller.selectedNodeIds, isEmpty);
  });

  test('change notifier follows controller events', () async {
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.addNode('source');
    await Future<void>.delayed(Duration.zero);

    expect(notifications, greaterThan(0));
  });

  test('layout actions align and distribute selected nodes', () {
    final first = controller.addNode('source', offset: const Offset(0, 80));
    final second = controller.addNode('source', offset: const Offset(100, 20));
    final third = controller.addNode('source', offset: const Offset(300, 160));
    controller.selectNodesById({first.id, second.id, third.id});

    controller.alignSelectedNodes(NodeAlignment.centerVertical);
    expect(controller.nodes[first.id]!.offset.dy, closeTo(86.667, 0.001));
    expect(controller.nodes[second.id]!.offset.dy, closeTo(86.667, 0.001));
    expect(controller.nodes[third.id]!.offset.dy, closeTo(86.667, 0.001));

    controller.distributeSelectedNodes(NodeDistributionAxis.horizontal);
    expect(controller.nodes[first.id]!.offset.dx, 0.0);
    expect(controller.nodes[second.id]!.offset.dx, 150.0);
    expect(controller.nodes[third.id]!.offset.dx, 300.0);
  });

  test('focus helpers are safe before the editor has been laid out', () {
    controller.addNode('source');

    expect(() => controller.focusAllNodes(animate: false), returnsNormally);
    expect(() => controller.resetViewport(animate: false), returnsNormally);
  });

  test('disabling snap is safe before any node has been dragged', () {
    final source = controller.addNode('source', offset: const Offset(13, 27));

    expect(() => controller.enableSnapToGrid(false), returnsNormally);
    expect(source.offset, const Offset(13, 27));
  });
}
