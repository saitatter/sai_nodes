# sai_nodes

Declarative graph editing in Flutter. This package renders the immutable
sai_nodes_core document and delegates all persisted changes to its controller.
It does not execute nodes or own application persistence.

```dart
import 'package:sai_nodes/sai_nodes.dart';

final definitions = NodeDefinitionRegistry()
  ..register(DeclarativeNodeDefinition(
    type: 'example.number',
    displayName: 'Number',
    ports: [StaticPortFamily([
      ResolvedPort(id: 'value', label: 'Value',
        direction: GraphPortDirection.output, kind: GraphPortKind.data,
        dataType: 'core.number'),
    ])],
  ));
final controller = GraphController(
  document: GraphDocument(id: 'document', spaces: {
    'main': GraphSpace(id: 'main', nodes: {
      'number': GraphNode(id: 'number', type: 'example.number', data: {'value': 42}),
    }),
  }),
  resolver: GraphResolver(definitions: definitions, types: GraphTypeSystem.core()),
);
// Place this widget inside a bounded Flutter layout:
final canvas = NodeEditor(controller: controller);
// The owner calls controller.dispose() when the document closes.
```

Default interactions cover selection, dragging, resizing, pan/zoom, connection
creation/reconnection, waypoints, frames, comments, minimap and keyboard commands.
Node/header/port/field builders share the default scene geometry. Optional host
clipboard hooks preserve semantic dependencies through copy/paste/duplicate.
An external GraphExecutionVisualSource supplies scoped activity and retained
results without modifying the document or rebuilding cached node bodies.

Version 1.0 replaces the 0.x API and formats completely. See the repository
example and docs/architecture.md for host integration and performance limits.
