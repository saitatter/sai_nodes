import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:test/test.dart';

GraphConnection edge(
  String id,
  String from,
  String to, {
  String sourcePort = 'value.out',
  String targetPort = 'value.in',
}) => GraphConnection(
  id: id,
  from: PortRef(nodeId: from, portId: sourcePort),
  to: PortRef(nodeId: to, portId: targetPort),
  kind: GraphConnectionKind.data,
);

GraphDocument example() => GraphDocument(
  id: 'document',
  spaces: {
    'main': GraphSpace(
      id: 'main',
      nodes: {
        'a': GraphNode(
          id: 'a',
          type: 'plugin.temporarily-missing',
          data: {
            'values': [
              1,
              true,
              null,
              {'nested': 'value'},
            ],
          },
          metadata: {'host': 'opaque'},
        ),
        'b': GraphNode(id: 'b', type: 'shader.float'),
      },
      connections: {
        'edge': edge('edge', 'a', 'b'),
        'unresolved': edge('unresolved', 'missing', 'b'),
      },
      nodePresentations: {
        'a': NodePresentation(
          nodeId: 'a',
          position: const GraphPoint(-50, 30),
          size: const GraphSize(120, 80),
          title: 'Alias',
          collapsed: true,
          metadata: {'color': '#ff00ff'},
        ),
      },
      connectionPresentations: {
        'edge': ConnectionPresentation(
          connectionId: 'edge',
          waypoints: [const GraphPoint(10, 20)],
          label: 'Value',
          labelOffset: const GraphPoint(2, 3),
          metadata: {'route': 'orthogonal'},
        ),
      },
      frames: {
        'frame': GraphFrame(
          id: 'frame',
          bounds: const GraphRect(-60, 20, 150, 100),
          title: 'Group',
          memberNodeIds: {'a'},
          autoFit: true,
          metadata: {'color': 'blue'},
        ),
      },
      comments: {
        'comment': GraphComment(
          id: 'comment',
          bounds: const GraphRect(10, 10, 80, 40),
          text: 'Notes',
          metadata: {'host': 42},
        ),
      },
      metadata: {'name': 'Main'},
    ),
    'subgraph': GraphSpace(id: 'subgraph'),
  },
  metadata: {
    'host': {'version': 1},
  },
);

void main() {
  test('pure Dart core imports no Flutter or dart:ui', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final source in sources) {
      expect(
        source.readAsStringSync(),
        isNot(
          matches(
            r'''(?:import|export)\s+['"](?:dart:ui|package:flutter(?:/|_))''',
          ),
        ),
        reason: source.path,
      );
    }
    final manifest = File('pubspec.yaml').readAsStringSync();
    expect(manifest, isNot(contains('sdk: flutter')));
  });

  test(
    'round trip preserves all entities, unresolved endpoints and host data',
    () {
      final document = example();
      final decoded = GraphDocument.fromJson(
        jsonDecode(jsonEncode(document.toJson())) as GraphJson,
      );
      expect(decoded, document);
      expect(decoded.hashCode, document.hashCode);
      expect(
        decoded.spaces['main']!.connections['unresolved']!.from.nodeId,
        'missing',
      );
      expect(
        decoded.toJson().keys,
        unorderedEquals(['schemaVersion', 'id', 'spaces', 'metadata']),
      );
      expect(
        const GraphDocumentValidator()
            .validate(decoded)
            .map((issue) => issue.code),
        ['missing-node'],
      );
    },
  );

  test('models detach maps, nested lists, frame members and waypoints', () {
    final nested = <Object?>[
      {
        'values': <Object?>[1],
      },
    ];
    final data = <String, Object?>{'nested': nested};
    final node = GraphNode(id: 'n', type: 'number', data: data);
    (nested.first as Map)['values'] = [999];
    data.clear();
    expect(node.data, {
      'nested': [
        {
          'values': [1],
        },
      ],
    });
    expect(() => node.data['other'] = 2, throwsUnsupportedError);
    expect(() => (node.data['nested'] as List).clear(), throwsUnsupportedError);
    final members = {'n'};
    final frame = GraphFrame(
      id: 'f',
      bounds: const GraphRect(0, 0, 10, 10),
      title: 'Frame',
      memberNodeIds: members,
    );
    members.clear();
    expect(frame.memberNodeIds, {'n'});
    expect(() => frame.memberNodeIds.add('x'), throwsUnsupportedError);
    final points = [const GraphPoint(1, 2)];
    final view = ConnectionPresentation(
      connectionId: 'edge',
      waypoints: points,
    );
    points.clear();
    expect(view.waypoints, [const GraphPoint(1, 2)]);
    expect(() => view.waypoints.clear(), throwsUnsupportedError);
    final nodes = {'n': node};
    final space = GraphSpace(id: 'main', nodes: nodes);
    nodes.clear();
    expect(space.nodes.keys, ['n']);
    expect(() => space.nodes.clear(), throwsUnsupportedError);
    final spaces = {'main': space};
    final document = GraphDocument(id: 'd', spaces: spaces);
    spaces.clear();
    expect(document.spaces.keys, ['main']);
    expect(() => document.spaces.clear(), throwsUnsupportedError);
  });

  test('JSON rejects cycles, mutable host objects and nonfinite numbers', () {
    final cyclic = <String, Object?>{};
    cyclic['self'] = cyclic;
    for (final data in [
      cyclic,
      {'value': Object()},
      {'value': double.nan},
      {
        'value': {1: 'bad'},
      },
    ]) {
      expect(
        () => GraphNode(id: 'n', type: 't', data: data),
        throwsArgumentError,
      );
    }
    final shared = <Object?>[1];
    expect(
      GraphNode(
        id: 'n',
        type: 't',
        data: {'one': shared, 'two': shared},
      ).data.length,
      2,
    );
  });

  test(
    'presentation edits preserve semantics and nullable values can be cleared',
    () {
      final document = example();
      final space = document.spaces['main']!;
      final moved = space.copyWith(
        nodePresentations: {
          'a': space.nodePresentations['a']!.copyWith(
            position: const GraphPoint(500, -20),
            size: null,
            title: null,
          ),
        },
      );
      expect(moved.nodes, space.nodes);
      expect(moved.connections, space.connections);
      expect(moved.nodePresentations['a']!.nodeId, 'a');
      expect(moved.nodePresentations['a']!.size, isNull);
      expect(moved.nodePresentations['a']!.title, isNull);
      expect(document.spaces['main']!.nodePresentations['a']!.title, 'Alias');
      final view = space.connectionPresentations['edge']!.copyWith(
        label: null,
        labelOffset: null,
      );
      expect(view.label, isNull);
      expect(view.labelOffset, isNull);
    },
  );

  test('new schema rejects unsupported versions and malformed fields', () {
    for (final value in [0, 2, 1.0, '1', null]) {
      expect(
        () => GraphDocument.fromJson({
          ...example().toJson(),
          'schemaVersion': value,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => GraphDocument.fromJson({...example().toJson(), 'legacy': {}}),
      throwsFormatException,
    );
    expect(
      () => GraphDocument.fromJson({...example().toJson(), 'spaces': []}),
      throwsFormatException,
    );
    final json = jsonDecode(jsonEncode(example().toJson())) as GraphJson;
    final spaces = json['spaces'] as Map;
    ((spaces['main'] as Map)['connections'] as Map)['edge']['kind'] = 'unknown';
    expect(() => GraphDocument.fromJson(json), throwsFormatException);
    final withNullSpaces = {...example().toJson(), 'spaces': null};
    expect(() => GraphDocument.fromJson(withNullSpaces), throwsFormatException);
  });

  test(
    'indexes cover parallel, self and unresolved edges without duplicate ownership',
    () {
      final space = GraphSpace(
        id: 'main',
        connections: {
          'one': edge('one', 'a', 'b'),
          'two': edge('two', 'a', 'b'),
          'self': edge('self', 'a', 'a'),
          'unknown': edge('unknown', 'missing', 'a'),
        },
      );
      final index = GraphIndexes.fromSpace(space);
      expect(index.connectionIdsByNode['a'], {'one', 'two', 'self', 'unknown'});
      expect(index.incomingConnectionIds['a'], {'self', 'unknown'});
      expect(index.outgoingConnectionIds['a'], {'one', 'two', 'self'});
      expect(
        index.connectionIdsByPort[const PortRef(
          nodeId: 'b',
          portId: 'value.in',
        )],
        {'one', 'two'},
      );
      expect(index.connectionIdsByNode['missing'], {'unknown'});
      expect(
        () => index.connectionIdsByNode['a']!.clear(),
        throwsUnsupportedError,
      );
      expect(() => index.connectionIdsByNode.clear(), throwsUnsupportedError);
      final updated = index.updatedFor(space.copyWith(connections: {}));
      expect(updated.connectionIdsByNode, isEmpty);
      expect(updated.connectionIdsByPort, isEmpty);
      expect(index.connectionIdsByNode['a'], {'one', 'two', 'self', 'unknown'});
    },
  );

  test(
    'incremental indexes match rebuilds and independent scans across random edits',
    () {
      final random = Random(42);
      var space = GraphSpace(id: 'main');
      var incremental = GraphIndexes.fromSpace(space);
      for (var step = 0; step < 120; step++) {
        final connections = {...space.connections};
        if (step % 3 == 0 && connections.isNotEmpty) {
          connections.remove(connections.keys.first);
        } else if (step % 5 == 0 && connections.isNotEmpty) {
          final id = connections.keys.first;
          connections[id] = edge(
            id,
            'n${random.nextInt(8)}',
            'n${random.nextInt(8)}',
            sourcePort: 'out-$step',
          );
        } else {
          connections['edge-$step'] = edge(
            'edge-$step',
            'n${random.nextInt(8)}',
            'n${random.nextInt(8)}',
          );
        }
        space = space.copyWith(connections: connections);
        final indexes = GraphIndexes.fromSpace(space);
        incremental = incremental.updatedFor(space);
        expect(incremental.connectionIdsByNode, indexes.connectionIdsByNode);
        expect(incremental.connectionIdsByPort, indexes.connectionIdsByPort);
        expect(
          incremental.incomingConnectionIds,
          indexes.incomingConnectionIds,
        );
        expect(
          incremental.outgoingConnectionIds,
          indexes.outgoingConnectionIds,
        );
        for (var n = 0; n < 8; n++) {
          final id = 'n$n';
          expect(
            indexes.connectionIdsByNode[id] ?? {},
            connections.entries
                .where(
                  (entry) =>
                      entry.value.from.nodeId == id ||
                      entry.value.to.nodeId == id,
                )
                .map((entry) => entry.key)
                .toSet(),
          );
          expect(
            indexes.incomingConnectionIds[id] ?? {},
            connections.entries
                .where((entry) => entry.value.to.nodeId == id)
                .map((entry) => entry.key)
                .toSet(),
          );
          expect(
            indexes.outgoingConnectionIds[id] ?? {},
            connections.entries
                .where((entry) => entry.value.from.nodeId == id)
                .map((entry) => entry.key)
                .toSet(),
          );
        }
      }
    },
  );

  test(
    'stable types provide exact, directional and explicitly configured any compatibility',
    () {
      final types = GraphTypeSystem.core(
        anyAccepts: {'core.string', 'shader.float'},
      );
      types.register(GraphDataType(id: 'shader.float', label: 'Float'));
      types.register(
        GraphDataType(
          id: 'host.duration',
          label: 'Duration',
          acceptedSourceTypeIds: {'core.number'},
        ),
      );
      expect(
        types.canConnect(outputType: 'shader.float', inputType: 'shader.float'),
        true,
      );
      expect(
        types.canConnect(outputType: 'shader.float', inputType: 'core.any'),
        true,
      );
      expect(
        types.canConnect(outputType: 'core.number', inputType: 'core.any'),
        false,
      );
      expect(
        types.canConnect(outputType: 'core.any', inputType: 'core.string'),
        false,
      );
      expect(
        types.canConnect(outputType: 'core.number', inputType: 'host.duration'),
        true,
      );
      expect(
        types.canConnect(outputType: 'host.duration', inputType: 'core.number'),
        false,
      );
      expect(
        types.canConnect(outputType: 'unregistered', inputType: 'core.any'),
        false,
      );
      expect(types.canConnect(outputType: '', inputType: ''), false);
      expect(
        () => types.register(
          GraphDataType(id: 'core.number', label: 'Duplicate'),
        ),
        throwsArgumentError,
      );
      expect(() => types.types.clear(), throwsUnsupportedError);
    },
  );

  test(
    'diagnostics preserve invalid connections, membership and presentation',
    () {
      final graph = GraphDocument(
        id: 'd',
        spaces: {
          'main': GraphSpace(
            id: 'wrong',
            nodes: {
              'a': GraphNode(id: 'a', type: 'host.type'),
              'b': GraphNode(id: 'a', type: ''),
            },
            connections: {'bad': edge('bad', 'gone', 'a', targetPort: '')},
            nodePresentations: {
              'orphan': NodePresentation(
                nodeId: 'orphan',
                position: const GraphPoint(double.infinity, 0),
              ),
            },
            connectionPresentations: {
              'orphan': ConnectionPresentation(
                connectionId: 'bad',
                waypoints: [const GraphPoint(0, double.nan)],
              ),
            },
            frames: {
              'f': GraphFrame(
                id: 'f',
                bounds: const GraphRect(0, 0, -1, 2),
                title: 'F',
                memberNodeIds: {'gone'},
              ),
            },
            comments: {
              'c': GraphComment(
                id: 'c',
                bounds: const GraphRect(0, 0, 3, -1),
                text: 'Invalid',
              ),
            },
          ),
        },
      );
      final issues = const GraphDocumentValidator().validate(graph);
      expect(
        issues.map((issue) => issue.code),
        containsAll([
          'identity-mismatch',
          'duplicate-id',
          'empty-node-type',
          'missing-node',
          'empty-port-id',
          'invalid-presentation-reference',
          'invalid-geometry',
          'invalid-waypoint',
          'invalid-frame-member',
        ]),
      );
      expect(issues.every((issue) => issue.spaceId == 'main'), true);
      expect(graph.spaces['main']!.connections.length, 1);
      expect(() => issues.clear(), throwsUnsupportedError);
    },
  );

  test('geometry uses world coordinates independently of Flutter', () {
    const point = GraphPoint(3, 4);
    expect(point.distanceTo(GraphPoint.zero), 5);
    expect(point + const GraphPoint(2, -1), const GraphPoint(5, 3));
    expect(point.scale(2), const GraphPoint(6, 8));
    final rect = GraphRect.fromPoints(
      const GraphPoint(10, 20),
      const GraphPoint(-5, -10),
    );
    expect(rect, const GraphRect(-5, -10, 15, 30));
    expect(rect.contains(const GraphPoint(-5, -10)), true);
    expect(rect.overlaps(const GraphRect(100, 100, 1, 1)), false);
    expect(
      rect.union(const GraphRect(10, 20, 5, 5)),
      const GraphRect(-5, -10, 20, 35),
    );
    expect(rect.translate(point).center, rect.center + point);
    expect(rect.inflate(2), const GraphRect(-7, -12, 19, 34));
    expect(const GraphRect(1e308, 0, 1e308, 10).isValid, false);
  });
}
