import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';

void main() {
  test('reconciles dynamic ports atomically and preserves compatible links',
      () async {
    final controller = NodeEditorController(
      config:
          const NodeEditorConfig(autoBuildGraph: false, autoRunGraph: false),
    );
    final input = ControlInputPortPrototype(
      idName: 'in',
      displayName: (_) => 'In',
      styleBuilder: defaultPortStyleBuilder,
    );
    final output = ControlOutputPortPrototype(
      idName: 'out',
      displayName: (_) => 'Out',
      styleBuilder: defaultPortStyleBuilder,
    );
    final extra = ControlInputPortPrototype(
      idName: 'extra',
      displayName: (_) => 'Extra',
      styleBuilder: defaultPortStyleBuilder,
    );
    controller.registerNodePrototype(_prototype('source', [output]));
    controller.registerNodePrototype(_prototype('target', [input]));

    final source = controller.addNode('source');
    final target = controller.addNode('target');
    final link = controller.addLink(source.id, 'out', target.id, 'in');
    expect(link, isNotNull);
    controller.history.clear();

    expect(
      controller.reconcileNodePorts(target.id, [input, extra]),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);
    expect(target.ports.keys, containsAll(<String>['in', 'extra']));
    expect(controller.links, containsPair(link!.id, link));
    expect(target.ports['in']!.links, contains(link));
    expect(controller.history.canUndo, isTrue);

    controller.history.undo();
    expect(target.ports.keys, ['in']);
    expect(controller.links, containsPair(link.id, isNotNull));
    controller.history.redo();
    expect(target.ports.keys, containsAll(<String>['in', 'extra']));
    expect(controller.links, containsPair(link.id, isNotNull));

    controller.dispose();
  });

  test('removes links that become incompatible in one history entry', () async {
    final controller = NodeEditorController(
      config:
          const NodeEditorConfig(autoBuildGraph: false, autoRunGraph: false),
    );
    final sourcePort = ControlOutputPortPrototype(
      idName: 'out',
      displayName: (_) => 'Out',
      styleBuilder: defaultPortStyleBuilder,
    );
    final controlInput = ControlInputPortPrototype(
      idName: 'in',
      displayName: (_) => 'In',
      styleBuilder: defaultPortStyleBuilder,
    );
    final dataInput = DataInputPortPrototype<String>(
      idName: 'in',
      displayName: (_) => 'Text',
      styleBuilder: defaultPortStyleBuilder,
    );
    controller.registerNodePrototype(_prototype('source', [sourcePort]));
    controller.registerNodePrototype(_prototype('target', [controlInput]));

    final source = controller.addNode('source');
    final target = controller.addNode('target');
    final link = controller.addLink(source.id, 'out', target.id, 'in');
    expect(link, isNotNull);
    controller.history.clear();

    expect(controller.reconcileNodePorts(target.id, [dataInput]), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(controller.links, isEmpty);
    expect(target.ports['in']!.prototype, same(dataInput));

    controller.history.undo();
    expect(controller.links, containsPair(link!.id, isNotNull));
    expect(target.ports['in']!.prototype, same(controlInput));
    controller.dispose();
  });

  test('rejects duplicate desired port identifiers without mutation', () {
    final controller = NodeEditorController(
      config:
          const NodeEditorConfig(autoBuildGraph: false, autoRunGraph: false),
    );
    final input = ControlInputPortPrototype(
      idName: 'in',
      displayName: (_) => 'In',
      styleBuilder: defaultPortStyleBuilder,
    );
    controller.registerNodePrototype(_prototype('target', [input]));
    final target = controller.addNode('target');

    expect(
      () => controller.reconcileNodePorts(target.id, [input, input]),
      throwsArgumentError,
    );
    expect(target.ports.keys, ['in']);
    expect(controller.history.canUndo, isFalse);
    controller.dispose();
  });
}

NodePrototype _prototype(String id, List<PortPrototype> ports) => NodePrototype(
      idName: id,
      displayName: (_) => id,
      description: (_) => id,
      ports: ports,
      onExecute: (ports, fields, state, forward, put) async {},
    );
