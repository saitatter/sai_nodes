import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:sai_nodes/sai_nodes.dart';

NodePrototype _prototype() => NodePrototype(
      idName: 'node',
      displayName: (_) => 'Node',
      description: (_) => 'Node',
      onExecute: (ports, fields, state, forward, put) async {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('alignment guides compare edges and centers in both axes', () {
    final controller = NodeEditorController(
      config: const NodeEditorConfig(
        enableSnapToGrid: false,
        autoBuildGraph: false,
        autoRunGraph: false,
      ),
    );
    addTearDown(controller.dispose);
    controller.registerNodePrototype(_prototype());

    final dragging = controller.addNode('node');
    final verticalReference = controller.addNode(
      'node',
      offset: const Offset(3, 200),
    );
    final horizontalReference = controller.addNode(
      'node',
      offset: const Offset(300, 104),
    );
    controller.resizeNode(dragging.id, const Size(100, 100));
    controller.resizeNode(verticalReference.id, const Size(100, 50));
    controller.resizeNode(horizontalReference.id, const Size(50, 100));

    final result = controller.alignmentGuidesFor({dragging.id});

    expect(
      result.guides,
      contains(
        const AlignmentGuide(
          axis: AlignmentGuideAxis.vertical,
          position: 3,
          from: 0,
          to: 100,
        ),
      ),
    );
    expect(
      result.guides,
      contains(
        const AlignmentGuide(
          axis: AlignmentGuideAxis.horizontal,
          position: 104,
          from: 0,
          to: 100,
        ),
      ),
    );
  });

  test('alignment guides exclude the dragged set and honor threshold', () {
    final controller = NodeEditorController(
      config: const NodeEditorConfig(
        enableSnapToGrid: false,
        autoBuildGraph: false,
        autoRunGraph: false,
      ),
    );
    addTearDown(controller.dispose);
    controller.registerNodePrototype(_prototype());

    final first = controller.addNode('node');
    final second = controller.addNode('node', offset: const Offset(103, 20));
    controller.resizeNode(first.id, const Size(100, 100));
    controller.resizeNode(second.id, const Size(100, 100));

    expect(
      controller.alignmentGuidesFor({first.id, second.id}).isEmpty,
      isTrue,
    );
    expect(
      controller.alignmentGuidesFor({first.id}, threshold: 1).isEmpty,
      isTrue,
    );
  });
}
