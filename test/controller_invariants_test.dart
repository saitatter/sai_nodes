import 'dart:ui' show Offset, Rect;

import 'package:sai_nodes/sai_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

NodePrototype _prototype({required String id, required bool input, required bool output}) =>
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
  late NodeEditorController controller;

  setUp(() {
    controller = NodeEditorController();
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
    controller.addLinkFromExisting(link!);

    expect(controller.links, hasLength(1));
    expect(source.ports['out']!.links, hasLength(1));
    expect(target.ports['in']!.links, hasLength(1));
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
    );

    final copy = original.copyWith(
      autoSave: false,
      autoBuildGraph: true,
      autoRunGraph: true,
      autoSaveInterval: const Duration(seconds: 21),
      manualSaveDebounce: const Duration(seconds: 22),
      autoBuildGraphDelay: const Duration(seconds: 23),
      autoRunGraphDelay: const Duration(seconds: 24),
    );

    expect(copy.autoSave, isFalse);
    expect(copy.autoBuildGraph, isTrue);
    expect(copy.autoRunGraph, isTrue);
    expect(copy.autoSaveInterval, const Duration(seconds: 21));
    expect(copy.manualSaveDebounce, const Duration(seconds: 22));
    expect(copy.autoBuildGraphDelay, const Duration(seconds: 23));
    expect(copy.autoRunGraphDelay, const Duration(seconds: 24));
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
}
