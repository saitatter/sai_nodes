import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:test/test.dart';

NodeDefinitionRegistry catalog() {
  final registry = NodeDefinitionRegistry();
  registry.register(
    DeclarativeNodeDefinition(
      type: 'number',
      displayName: 'Number',
      ports: [
        StaticPortFamily([
          ResolvedPort(
            id: 'value.in',
            direction: GraphPortDirection.input,
            kind: GraphPortKind.data,
            dataType: 'core.number',
            label: 'Value',
            maxConnections: 1,
          ),
          ResolvedPort(
            id: 'value.out',
            direction: GraphPortDirection.output,
            kind: GraphPortKind.data,
            dataType: 'core.number',
            label: 'Value',
          ),
        ]),
      ],
    ),
  );
  return registry;
}

GraphController controller({int capacity = 100}) => GraphController(
  document: GraphDocument(
    id: 'd',
    spaces: {'main': GraphSpace(id: 'main')},
  ),
  resolver: GraphResolver(
    definitions: catalog(),
    types: GraphTypeSystem.core(),
  ),
  historyCapacity: capacity,
);
AddNodeCommand add(String id, {GraphPoint point = GraphPoint.zero}) =>
    AddNodeCommand(
      'main',
      GraphNode(id: id, type: 'number', data: {'value': 1}),
      presentation: NodePresentation(nodeId: id, position: point),
    );
GraphConnection wire(
  String id,
  String from,
  String to, {
  String port = 'value.in',
}) => GraphConnection(
  id: id,
  from: PortRef(nodeId: from, portId: 'value.out'),
  to: PortRef(nodeId: to, portId: port),
  kind: GraphConnectionKind.data,
);

void main() {
  test(
    'host paste preparation and data remapping commit and undo atomically',
    () {
      final graph = controller();
      addTearDown(graph.dispose);
      graph.execute(add('source'));
      graph.select(GraphSelection(nodes: {'source'}));
      final fragment = GraphFragment.capture(graph);
      final before = graph.document;
      graph.pasteGraphFragment(
        fragment,
        idFactory: () => 'copied',
        transformRemapped: (prepared, ids) => prepared.copyWith(
          nodes: {
            'copied': prepared.nodes['copied']!.copyWith(
              data: {'origin': ids['source']},
            ),
          },
        ),
        prepareTransaction: (tx) =>
            tx.execute(UpdateDocumentMetadataCommand({'dependency': 'added'})),
      );
      expect(graph.activeSpace!.nodes['copied']!.data['origin'], 'copied');
      expect(graph.document.metadata['dependency'], 'added');
      graph.undo();
      expect(graph.document, before);
      expect(
        () => graph.pasteGraphFragment(
          fragment,
          prepareTransaction: (tx) {
            tx.execute(UpdateDocumentMetadataCommand({'partial': true}));
            throw StateError('Host rejected dependency');
          },
        ),
        throwsStateError,
      );
      expect(graph.document, before);
    },
  );
  test('paste reserves entity IDs in every space', () {
    final graph = controller();
    addTearDown(graph.dispose);
    graph.execute(add('source'));
    graph.execute(
      AddSpaceCommand(
        GraphSpace(
          id: 'other',
          nodes: {'reserved': GraphNode(id: 'reserved', type: 'number')},
        ),
      ),
    );
    graph.select(GraphSelection(nodes: {'source'}));
    final before = graph.document;
    expect(
      () => graph.pasteGraphFragment(
        GraphFragment.capture(graph),
        idFactory: () => 'reserved',
      ),
      throwsStateError,
    );
    expect(graph.document, before);
  });
  test(
    'an asynchronous save marks its captured revision and preserves later edits',
    () {
      final graph = controller();
      addTearDown(graph.dispose);
      graph.markUnsaved();
      expect(graph.isDirty, true);
      graph.execute(add('a'));
      final savingRevision = graph.revision;
      graph.execute(add('b'));
      graph.markSaved(revision: savingRevision);
      expect(graph.isDirty, true);
      graph.undo();
      expect(graph.isDirty, false);
      graph.redo();
      expect(graph.isDirty, true);
    },
  );
  test(
    'host policy commits atomically and throwing rolls back the full edit',
    () {
      final graph = GraphController(
        document: GraphDocument(
          id: 'd',
          spaces: {'main': GraphSpace(id: 'main')},
        ),
        resolver: GraphResolver(
          definitions: catalog(),
          types: GraphTypeSystem.core(),
        ),
        documentPolicy: (before, next) {
          if (next.spaces['main']!.nodes.containsKey('rejected')) {
            throw StateError('Host rejected this edit');
          }
          return next.copyWith(
            metadata: {'count': next.spaces['main']!.nodes.length},
          );
        },
      );
      addTearDown(graph.dispose);
      var notices = 0;
      graph.addDocumentListener((_) => notices++);
      graph.execute(add('a'));
      expect(graph.document.metadata['count'], 1);
      expect(notices, 1);
      final committed = graph.document;
      expect(() => graph.execute(add('rejected')), throwsStateError);
      expect(graph.document, same(committed));
      expect(notices, 1);
      graph.undo();
      expect(graph.document.metadata['count'], 0);
      expect(graph.activeSpace!.nodes, isEmpty);
      expect(graph.isDirty, false);
      graph.redo();
      expect(graph.document, committed);
    },
  );
  test(
    'auto-fit and containment membership are resolved in the same transaction',
    () {
      final graph = controller();
      addTearDown(graph.dispose);
      graph.execute(add('a', point: const GraphPoint(50, 60)));
      graph.execute(
        CreateFrameCommand(
          'main',
          GraphFrame(
            id: 'auto',
            bounds: const GraphRect(0, 0, 600, 400),
            title: 'Auto',
            autoFit: true,
            memberNodeIds: {'a'},
          ),
        ),
      );
      var notices = 0;
      graph.addDocumentListener((_) => notices++);
      final before = graph.document;
      graph.execute(
        MoveNodesCommand('main', {'a': const GraphPoint(250, 260)}),
      );
      expect(notices, 1);
      expect(graph.activeSpace!.frames['auto']!.bounds.left, 226);
      graph.undo();
      expect(graph.document, before);
      graph.execute(
        CreateFrameCommand(
          'main',
          GraphFrame(
            id: 'contains',
            bounds: const GraphRect(0, 0, 600, 400),
            title: 'Contains',
            metadata: {'membership': 'contains'},
          ),
        ),
      );
      expect(graph.activeSpace!.frames['contains']!.memberNodeIds, {'a'});
      graph.execute(
        MoveNodesCommand('main', {'a': const GraphPoint(900, 900)}),
      );
      expect(graph.activeSpace!.frames['contains']!.memberNodeIds, isEmpty);
    },
  );
  test(
    'compound commit is synchronous, resolved, indexed and notified once',
    () {
      final graph = controller();
      addTearDown(graph.dispose);
      final notifications = <GraphDocumentChange>[];
      graph.addDocumentListener((change) {
        notifications.add(change);
        expect(graph.document.spaces['main']!.connections.keys, ['edge']);
        expect(graph.indexes['main']!.incomingConnectionIds['b'], {'edge'});
        expect(graph.resolution.diagnostics, isEmpty);
      });
      graph.transaction((tx) {
        tx.execute(add('a'));
        tx.execute(add('b'));
        tx.execute(AddConnectionCommand('main', wire('edge', 'a', 'b')));
      }, label: 'Create chain');
      expect(notifications.length, 1);
      expect(notifications.single.changes.addedNodeIds, {'a', 'b'});
      expect(notifications.single.changes.addedConnectionIds, {'edge'});
      expect(graph.undoCount, 1);
    },
  );
  test(
    'failed validation and thrown commands rollback document, indexes, revisions and history',
    () {
      final graph = controller();
      addTearDown(graph.dispose);
      graph.execute(add('a'));
      final before = graph.document, revision = graph.revision;
      var notifications = 0;
      graph.addListener(() => notifications++);
      expect(
        () => graph.transaction((tx) {
          tx.execute(add('b'));
          tx.execute(
            AddConnectionCommand(
              'main',
              wire('bad', 'a', 'b', port: 'missing'),
            ),
          );
        }, label: 'Invalid connection'),
        throwsA(isA<GraphMutationException>()),
      );
      expect(graph.document, same(before));
      expect(graph.revision, revision);
      expect(graph.undoCount, 1);
      expect(notifications, 0);
      expect(
        () => graph.transaction((tx) {
          tx.execute(add('b'));
          tx.execute(add('a'));
        }, label: 'Duplicate'),
        throwsStateError,
      );
      expect(graph.document, same(before));
      expect(graph.indexes['main']!.connectionIdsByNode, isEmpty);
    },
  );
  test(
    'undo and redo restore removed wires, annotations and frame membership',
    () {
      final graph = controller();
      addTearDown(graph.dispose);
      graph.transaction((tx) {
        tx.execute(add('a'));
        tx.execute(add('b'));
        tx.execute(AddConnectionCommand('main', wire('edge', 'a', 'b')));
        tx.execute(
          UpdateConnectionPresentationCommand(
            'main',
            ConnectionPresentation(
              connectionId: 'edge',
              label: 'Count',
              waypoints: [const GraphPoint(20, 30)],
            ),
          ),
        );
        tx.execute(
          CreateFrameCommand(
            'main',
            GraphFrame(
              id: 'f',
              bounds: const GraphRect(0, 0, 300, 200),
              title: 'Group',
              memberNodeIds: {'a', 'b'},
            ),
          ),
        );
      }, label: 'Fixture');
      final before = graph.document;
      graph.execute(RemoveNodesCommand('main', {'a'}));
      expect(graph.activeSpace!.connections, isEmpty);
      expect(graph.activeSpace!.frames['f']!.memberNodeIds, {'b'});
      graph.undo();
      expect(graph.document, before);
      graph.redo();
      expect(graph.activeSpace!.nodes.keys, ['b']);
      graph.undo();
      graph.execute(const UpdateNodeDataCommand('main', 'a', {'value': 5}));
      expect(graph.canRedo, false);
    },
  );
  test(
    'presentation edits do not invalidate semantics and saved revision survives undo',
    () {
      final graph = controller();
      addTearDown(graph.dispose);
      graph.execute(add('a'));
      graph.markSaved();
      final semantic = graph.semanticRevision;
      graph.execute(MoveNodesCommand('main', {'a': const GraphPoint(10, 20)}));
      expect(graph.semanticRevision, semantic);
      expect(graph.isDirty, true);
      graph.undo();
      expect(graph.isDirty, false);
      graph.redo();
      expect(graph.isDirty, true);
      graph.execute(const UpdateNodeDataCommand('main', 'a', {'value': 2}));
      expect(graph.semanticRevision, greaterThan(semantic));
    },
  );
  test(
    'drag coalescing, bounded history and save barriers are deterministic',
    () {
      final graph = controller(capacity: 2);
      addTearDown(graph.dispose);
      graph.execute(add('a'));
      graph.markSaved();
      for (var i = 1; i <= 10; i++) {
        graph.execute(
          MoveNodesCommand('main', {'a': GraphPoint(i.toDouble(), 0)}),
          coalesceKey: 'drag-1',
        );
      }
      expect(graph.undoCount, 2);
      graph.undo();
      expect(
        graph.activeSpace!.nodePresentations['a']!.position,
        GraphPoint.zero,
      );
      expect(graph.isDirty, false);
      graph.redo();
      graph.markSaved();
      graph.execute(
        MoveNodesCommand('main', {'a': const GraphPoint(20, 0)}),
        coalesceKey: 'drag-1',
      );
      graph.undo();
      expect(graph.isDirty, false);
      expect(
        graph.activeSpace!.nodePresentations['a']!.position,
        const GraphPoint(10, 0),
      );
    },
  );
  test(
    'camera, space switching and selection are ephemeral; loading is atomic',
    () {
      final graph = controller();
      addTearDown(graph.dispose);
      graph.execute(add('a'));
      graph.execute(AddSpaceCommand(GraphSpace(id: 'second')));
      graph.markSaved();
      final revision = graph.revision;
      graph.select(GraphSelection(nodes: {'a'}));
      graph.setCamera(graph.camera.pan(const GraphPoint(20, 10)));
      graph.setActiveSpace('second');
      expect(graph.selection.isEmpty, true);
      expect(graph.revision, revision);
      expect(graph.isDirty, false);
      final before = graph.document;
      graph.replaceDocument(
        GraphDocument(
          id: 'loaded',
          spaces: {'new': GraphSpace(id: 'new')},
        ),
      );
      expect(graph.activeSpaceId, 'new');
      expect(graph.canUndo, false);
      expect(graph.isDirty, false);
      graph.replaceDocument(before, markSaved: false);
      expect(graph.isDirty, true);
      expect(graph.activeSpaceId, 'main');
    },
  );
  test(
    'camera anchor stays fixed under zoom and focus bounds uses viewport',
    () {
      const camera = GraphCamera(offset: GraphPoint(30, -20), zoom: 2);
      const anchor = GraphPoint(100, 200);
      expect(
        camera.zoomAt(anchor, 1.5).viewportToWorld(anchor),
        camera.viewportToWorld(anchor),
      );
      final focused = camera.focusBounds(
        const GraphRect(0, 0, 100, 100),
        const GraphSize(500, 500),
      );
      expect(
        focused.worldToViewport(const GraphPoint(50, 50)),
        const GraphPoint(250, 250),
      );
    },
  );
  test('clipboard allocates new IDs for every entity and commits once', () {
    final graph = controller();
    addTearDown(graph.dispose);
    graph.transaction((tx) {
      tx.execute(add('a'));
      tx.execute(add('b', point: const GraphPoint(100, 0)));
      tx.execute(AddConnectionCommand('main', wire('edge', 'a', 'b')));
      tx.execute(
        CreateFrameCommand(
          'main',
          GraphFrame(
            id: 'f',
            bounds: const GraphRect(0, 0, 200, 100),
            title: 'Group',
            memberNodeIds: {'a', 'b'},
          ),
        ),
      );
      tx.execute(
        CreateCommentCommand(
          'main',
          GraphComment(
            id: 'c',
            bounds: const GraphRect(10, 100, 80, 40),
            text: 'Note',
          ),
        ),
      );
    }, label: 'Fixture');
    graph.select(GraphSelection(frames: {'f'}, comments: {'c'}));
    final fragment = GraphFragment.decode(
      GraphFragment.capture(graph, hostPayload: {'plugin': 'host'}).encode(),
    );
    expect(fragment.hostPayload, {'plugin': 'host'});
    var next = 0;
    final before = graph.document;
    final history = graph.undoCount;
    final pasted = graph.pasteGraphFragment(
      fragment,
      idFactory: () => 'fresh-${next++}',
      offset: const GraphPoint(50, 60),
    );
    expect(graph.undoCount, history + 1);
    expect(pasted.nodes.length, 2);
    expect(pasted.frames.length, 1);
    expect(pasted.comments.length, 1);
    final edge = graph.activeSpace!.connections[pasted.connections.single]!;
    expect(pasted.nodes.contains(edge.from.nodeId), true);
    expect(pasted.nodes.contains(edge.to.nodeId), true);
    expect(
      graph.activeSpace!.frames[pasted.frames.single]!.memberNodeIds,
      pasted.nodes,
    );
    graph.undo();
    expect(graph.document, before);
    graph.redo();
    expect(graph.activeSpace!.nodes.length, 4);
  });
  test(
    'paste and splice fail atomically; valid splice keeps original connection ID',
    () {
      final graph = controller();
      addTearDown(graph.dispose);
      graph.transaction((tx) {
        tx.execute(add('a'));
        tx.execute(add('b'));
        tx.execute(AddConnectionCommand('main', wire('edge', 'a', 'b')));
      }, label: 'Chain');
      final before = graph.document;
      expect(
        () => graph.pasteGraphFragment(
          GraphFragment(
            space: GraphSpace(
              id: 'f',
              nodes: {'x': GraphNode(id: 'x', type: 'number')},
              connections: {'external': wire('external', 'x', 'outside')},
            ),
          ),
        ),
        throwsFormatException,
      );
      expect(graph.document, before);
      expect(
        () => graph.spliceNodeIntoConnection(
          'edge',
          GraphNode(id: 'unknown', type: 'missing'),
        ),
        throwsStateError,
      );
      expect(graph.document, before);
      graph.spliceNodeIntoConnection(
        'edge',
        GraphNode(id: 'middle', type: 'number'),
        idFactory: () => 'after',
      );
      expect(graph.activeSpace!.connections['edge']!.to.nodeId, 'middle');
      expect(graph.activeSpace!.connections['after']!.to.nodeId, 'b');
      graph.undo();
      expect(graph.document, before);
    },
  );
  test(
    'every annotation command supports undo/redo and frame movement moves members',
    () {
      final graph = controller();
      addTearDown(graph.dispose);
      graph.execute(add('a'));
      final commands = <GraphCommand>[
        ResizeNodesCommand('main', {'a': const GraphSize(250, 150)}),
        const SetNodeTitleCommand('main', 'a', 'Title'),
        const SetNodeCollapsedCommand('main', 'a', true),
        CreateFrameCommand(
          'main',
          GraphFrame(
            id: 'f',
            bounds: const GraphRect(0, 0, 300, 200),
            title: 'Frame',
            memberNodeIds: {'a'},
          ),
        ),
        UpdateFrameCommand(
          'main',
          GraphFrame(
            id: 'f',
            bounds: const GraphRect(0, 0, 400, 200),
            title: 'Renamed',
            memberNodeIds: {'a'},
          ),
        ),
        CreateCommentCommand(
          'main',
          GraphComment(
            id: 'c',
            bounds: const GraphRect(0, 200, 150, 60),
            text: 'Note',
          ),
        ),
        UpdateCommentCommand(
          'main',
          GraphComment(
            id: 'c',
            bounds: const GraphRect(20, 200, 150, 60),
            text: 'Changed',
          ),
        ),
        const RemoveCommentCommand('main', 'c'),
        const RemoveFrameCommand('main', 'f'),
      ];
      for (final command in commands) {
        final before = graph.document;
        graph.execute(command);
        final after = graph.document;
        graph.undo();
        expect(graph.document, before);
        graph.redo();
        expect(graph.document, after);
      }
      graph.execute(
        CreateFrameCommand(
          'main',
          GraphFrame(
            id: 'f',
            bounds: const GraphRect(0, 0, 400, 200),
            title: 'Move',
            memberNodeIds: {'a'},
          ),
        ),
      );
      final before = graph.document;
      graph.moveFrameWithMembers('f', const GraphPoint(10, 20));
      expect(
        graph.activeSpace!.nodePresentations['a']!.position,
        const GraphPoint(10, 20),
      );
      graph.undo();
      expect(graph.document, before);
    },
  );
  test(
    'registry changes re-resolve immediately without dirtying persistence',
    () {
      final graph = controller();
      addTearDown(graph.dispose);
      graph.execute(add('a'));
      graph.markSaved();
      graph.resolver.definitions.unregister('number');
      expect(
        graph.resolution.diagnostics.map((issue) => issue.code),
        contains('missing-definition'),
      );
      expect(graph.isDirty, false);
      expect(graph.activeSpace!.nodes.length, 1);
      graph.resolver.definitions.register(catalog()['number']!);
      expect(graph.resolution.diagnostics, isEmpty);
      expect(graph.isDirty, false);
    },
  );
}
