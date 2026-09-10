import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:sai_nodes/sai_nodes.dart';

NodePrototype _prototype(
  String id, {
  required List<PortPrototype> ports,
}) =>
    NodePrototype(
      idName: id,
      displayName: (_) => id,
      description: (_) => id,
      ports: ports,
      onExecute: (ports, fields, state, forward, put) async {},
    );

PortStyle _portStyle(LinkCurveType curve) => PortStyle(
      shape: PortShape.circle,
      color: const Color(0xff42a5f5),
      radius: 5,
      linkStyleBuilder: (_) => LinkStyle(
        lineWidth: 2,
        drawMode: LineDrawMode.solid,
        curveType: curve,
      ),
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
  });

  tearDown(() => controller.dispose());

  test('hitTestNode uses world bounds and returns the topmost node', () {
    controller.registerNodePrototype(
      _prototype('node', ports: const []),
    );
    final bottom = controller.addNode('node', offset: const Offset(20, 20));
    final top = controller.addNode('node', offset: const Offset(60, 50));
    controller.resizeNode(bottom.id, const Size(120, 100));
    controller.resizeNode(top.id, const Size(120, 100));

    final result = controller.hitTestNode(const Offset(80, 80));

    expect(result?.nodeId, top.id);
    expect(result?.bounds, const Rect.fromLTWH(60, 50, 120, 100));
    expect(controller.hitTestNode(const Offset(300, 300)), isNull);
  });

  test('hitTestNode supports host filters and default pre-layout bounds', () {
    controller.registerNodePrototype(
      _prototype('node', ports: const []),
    );
    final node = controller.addNode('node', offset: const Offset(10, 15));

    expect(
      controller.hitTestNode(const Offset(20, 25), where: (_) => false),
      isNull,
    );
    expect(
      controller.hitTestNode(const Offset(20, 25))?.nodeId,
      node.id,
    );
  });

  test('hitTestLink delegates curve geometry and returns distance', () {
    final sourcePort = ControlOutputPortPrototype(
      idName: 'out',
      displayName: (_) => 'Output',
      styleBuilder: (_) => _portStyle(LinkCurveType.bezier),
    );
    final targetPort = ControlInputPortPrototype(
      idName: 'in',
      displayName: (_) => 'Input',
      styleBuilder: (_) => _portStyle(LinkCurveType.bezier),
    );
    controller.registerNodePrototype(
      _prototype('source', ports: [sourcePort]),
    );
    controller.registerNodePrototype(
      _prototype('target', ports: [targetPort]),
    );

    final source = controller.addNode('source');
    final target = controller.addNode('target', offset: const Offset(400, 0));
    source.ports['out']!.offset = const Offset(200, 50);
    target.ports['in']!.offset = const Offset(0, 50);
    final link = controller.addLink(source.id, 'out', target.id, 'in');

    expect(link, isNotNull);
    final result = controller.hitTestLink(
      const Offset(300, 50),
      tolerance: 1,
    );

    expect(result?.linkId, link!.id);
    expect(result?.curveType, LinkCurveType.bezier);
    expect(result?.distance, lessThanOrEqualTo(1));
    expect(
      controller.hitTestLink(const Offset(300, 60), tolerance: 5),
      isNull,
    );
  });

  test('hitTestLink applies host link filters and skips broken links', () {
    final sourcePort = ControlOutputPortPrototype(
      idName: 'out',
      displayName: (_) => 'Output',
      styleBuilder: defaultPortStyleBuilder,
    );
    final targetPort = ControlInputPortPrototype(
      idName: 'in',
      displayName: (_) => 'Input',
      styleBuilder: defaultPortStyleBuilder,
    );
    controller.registerNodePrototype(
      _prototype('source', ports: [sourcePort]),
    );
    controller.registerNodePrototype(
      _prototype('target', ports: [targetPort]),
    );
    final source = controller.addNode('source');
    final target = controller.addNode('target', offset: const Offset(300, 0));
    source.ports['out']!.offset = const Offset(200, 25);
    target.ports['in']!.offset = const Offset(0, 25);
    final link = controller.addLink(source.id, 'out', target.id, 'in')!;

    expect(
      controller.hitTestLink(
        const Offset(250, 25),
        where: (_) => false,
      ),
      isNull,
    );
    expect(
      controller
          .hitTestLink(
            const Offset(250, 25),
            where: (candidate) => candidate.id == link.id,
          )
          ?.linkId,
      link.id,
    );
  });
}
