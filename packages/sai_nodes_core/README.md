# sai_nodes_core

Pure Dart foundations for the Sai Nodes 1.0 graph editor rewrite.

The immutable `GraphDocument` owns spaces, nodes, connections, presentations,
frames and comments. Connections are stored once. Nested semantic JSON is copied
and frozen. `GraphIndexes` derives adjacency caches, `GraphTypeSystem` uses stable
string IDs, and `GraphDocumentValidator` reports structural problems without
removing unresolved entities.

```dart
import 'package:sai_nodes_core/sai_nodes_core.dart';

final document = GraphDocument(id: 'automation', spaces: {
  'main': GraphSpace(id: 'main', nodes: {
    'constant': GraphNode(id: 'constant', type: 'example.number', data: {'value': 42}),
  }),
});
final diagnostics = const GraphDocumentValidator().validate(document);
```

This is Phase A of an ongoing rewrite. Commands, transactions, definitions,
dynamic resolution and the Flutter scene are subsequent phases. The new document
codec supports only schema version 1; it has no legacy format decoder.

Run `dart test` in this package. From the workspace root,
`dart run tool/verify_core_isolation.dart` also resolves and tests a standalone
copy without Flutter.
