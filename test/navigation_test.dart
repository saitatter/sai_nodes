import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';

void main() {
  test('navigates selection without a mounted Flutter widget tree', () {
    final controller = NodeEditorController(
      config: const NodeEditorConfig(
        autoBuildGraph: false,
        autoRunGraph: false,
      ),
    );
    addTearDown(controller.dispose);

    controller.registerNodePrototype(
      NodePrototype(
        idName: 'test.node',
        displayName: (_) => 'Node',
        description: (_) => 'Node',
        onExecute: (ports, fields, state, forward, put) async {},
      ),
    );

    final origin = controller.addNode('test.node');
    final next = controller.addNode(
      'test.node',
      offset: const Offset(120, 0),
    );
    controller.selectNodesById({origin.id});

    expect(
      controller.navigateSelection(NodeNavigationDirection.right),
      next.id,
    );
    expect(controller.selectedNodeIds, {next.id});
  });
}
