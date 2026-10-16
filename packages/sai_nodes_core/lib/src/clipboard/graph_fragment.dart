import 'dart:convert';
import 'dart:math';

import '../commands/graph_commands.dart';
import '../controller/graph_controller.dart';
import '../definitions/node_definition.dart';
import '../geometry/geometry.dart';
import '../model/graph_document.dart';
import '../model/immutable_json.dart';

typedef GraphIdFactory = String Function();

enum GraphNodeAlignment { left, center, right, top, middle, bottom }

enum GraphDistributionAxis { horizontal, vertical }

final _random = Random.secure();
String newGraphId() => List.generate(
  16,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

final class GraphFragment {
  GraphFragment({required this.space, GraphJson hostPayload = const {}})
    : hostPayload = freezeJson(hostPayload);
  final GraphSpace space;
  final GraphJson hostPayload;
  String encode() => jsonEncode({
    'format': 'sai-nodes-fragment',
    'version': 1,
    'graph': GraphDocument(id: 'fragment', spaces: {space.id: space}).toJson(),
    'hostPayload': hostPayload,
  });
  factory GraphFragment.decode(String value) {
    final json = jsonDecode(value);
    if (json is! Map<String, dynamic> ||
        json['format'] != 'sai-nodes-fragment' ||
        json['version'] != 1 ||
        json['graph'] is! Map<String, dynamic> ||
        json.keys.any(
          (key) => !{'format', 'version', 'graph', 'hostPayload'}.contains(key),
        )) {
      throw const FormatException('Unsupported graph fragment.');
    }
    final document = GraphDocument.fromJson(json['graph'] as GraphJson);
    if (document.spaces.length != 1) {
      throw const FormatException('A fragment requires exactly one space.');
    }
    final payload = json['hostPayload'] ?? <String, Object?>{};
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Invalid fragment host payload.');
    }
    return GraphFragment(
      space: document.spaces.values.single,
      hostPayload: payload,
    );
  }
  factory GraphFragment.capture(
    GraphController controller, {
    GraphJson hostPayload = const {},
  }) {
    final space = controller.activeSpace;
    if (space == null) throw StateError('No active graph space.');
    final selection = controller.selection;
    final nodeIds = {...selection.nodes};
    for (final id in selection.frames) {
      nodeIds.addAll(space.frames[id]?.memberNodeIds ?? {});
    }
    final edges = Map<String, GraphConnection>.fromEntries(
      space.connections.entries.where(
        (entry) =>
            nodeIds.contains(entry.value.from.nodeId) &&
            nodeIds.contains(entry.value.to.nodeId),
      ),
    );
    return GraphFragment(
      space: GraphSpace(
        id: 'fragment',
        nodes: Map.fromEntries(
          space.nodes.entries.where((entry) => nodeIds.contains(entry.key)),
        ),
        nodePresentations: Map.fromEntries(
          space.nodePresentations.entries.where(
            (entry) => nodeIds.contains(entry.key),
          ),
        ),
        connections: edges,
        connectionPresentations: Map.fromEntries(
          space.connectionPresentations.entries.where(
            (entry) => edges.containsKey(entry.key),
          ),
        ),
        frames: Map.fromEntries(
          space.frames.entries.where(
            (entry) => selection.frames.contains(entry.key),
          ),
        ),
        comments: Map.fromEntries(
          space.comments.entries.where(
            (entry) => selection.comments.contains(entry.key),
          ),
        ),
      ),
      hostPayload: hostPayload,
    );
  }
}

/// Generic compound operations. Each helper uses the same transaction history.
extension GraphEditingOperations on GraphController {
  void alignSelection(
    GraphNodeAlignment alignment,
    Map<String, GraphRect> bounds,
  ) {
    final sid = activeSpaceId;
    if (sid == null) return;
    final ids = selection.nodes.where(bounds.containsKey).toList();
    if (ids.length < 2) return;
    final union = ids.map((id) => bounds[id]!).reduce((a, b) => a.union(b));
    final positions = <String, GraphPoint>{};
    for (final id in ids) {
      final rect = bounds[id]!;
      positions[id] = switch (alignment) {
        GraphNodeAlignment.left => GraphPoint(union.left, rect.top),
        GraphNodeAlignment.center => GraphPoint(
          union.center.x - rect.width / 2,
          rect.top,
        ),
        GraphNodeAlignment.right => GraphPoint(
          union.right - rect.width,
          rect.top,
        ),
        GraphNodeAlignment.top => GraphPoint(rect.left, union.top),
        GraphNodeAlignment.middle => GraphPoint(
          rect.left,
          union.center.y - rect.height / 2,
        ),
        GraphNodeAlignment.bottom => GraphPoint(
          rect.left,
          union.bottom - rect.height,
        ),
      };
    }
    execute(MoveNodesCommand(sid, positions), label: 'Align nodes');
  }

  void distributeSelection(
    GraphDistributionAxis axis,
    Map<String, GraphRect> bounds,
  ) {
    final sid = activeSpaceId;
    if (sid == null) return;
    final horizontal = axis == GraphDistributionAxis.horizontal;
    final ids = selection.nodes.where(bounds.containsKey).toList()
      ..sort(
        (a, b) => (horizontal ? bounds[a]!.left : bounds[a]!.top).compareTo(
          horizontal ? bounds[b]!.left : bounds[b]!.top,
        ),
      );
    if (ids.length < 3) return;
    final first = bounds[ids.first]!, last = bounds[ids.last]!;
    final start = horizontal ? first.left : first.top,
        end = horizontal ? last.right : last.bottom;
    final total = ids
        .map((id) => horizontal ? bounds[id]!.width : bounds[id]!.height)
        .fold(0.0, (a, b) => a + b);
    final gap = (end - start - total) / (ids.length - 1);
    var cursor = start;
    final positions = <String, GraphPoint>{};
    for (final id in ids) {
      final rect = bounds[id]!;
      positions[id] = horizontal
          ? GraphPoint(cursor, rect.top)
          : GraphPoint(rect.left, cursor);
      cursor += (horizontal ? rect.width : rect.height) + gap;
    }
    execute(MoveNodesCommand(sid, positions), label: 'Distribute nodes');
  }

  GraphSelection pasteGraphFragment(
    GraphFragment fragment, {
    GraphPoint offset = const GraphPoint(24, 24),
    GraphIdFactory idFactory = newGraphId,
    GraphFragment Function(GraphFragment)? enrich,
  }) {
    final source = (enrich?.call(fragment) ?? fragment).space;
    final sid = activeSpaceId;
    if (sid == null) throw StateError('No active space.');
    final reserved = <String>{
      ...activeSpace!.nodes.keys,
      ...activeSpace!.connections.keys,
      ...activeSpace!.frames.keys,
      ...activeSpace!.comments.keys,
    };
    String allocate() {
      final id = idFactory();
      if (id.isEmpty || !reserved.add(id)) {
        throw StateError('ID factory must allocate unique, fresh IDs.');
      }
      return id;
    }

    final nodes = {for (final id in source.nodes.keys) id: allocate()};
    final edges = {for (final id in source.connections.keys) id: allocate()};
    final frames = {for (final id in source.frames.keys) id: allocate()};
    final comments = {for (final id in source.comments.keys) id: allocate()};
    for (final edge in source.connections.values) {
      if (!nodes.containsKey(edge.from.nodeId) ||
          !nodes.containsKey(edge.to.nodeId)) {
        throw const FormatException(
          'Fragment contains an external connection endpoint.',
        );
      }
    }
    final prepared = GraphSpace(
      id: 'fragment',
      nodes: {
        for (final entry in source.nodes.entries)
          nodes[entry.key]!: GraphNode(
            id: nodes[entry.key]!,
            type: entry.value.type,
            data: entry.value.data,
            metadata: entry.value.metadata,
          ),
      },
      nodePresentations: {
        for (final entry in source.nodes.entries)
          nodes[entry.key]!: NodePresentation(
            nodeId: nodes[entry.key]!,
            position:
                (source.nodePresentations[entry.key]?.position ??
                    GraphPoint.zero) +
                offset,
            size: source.nodePresentations[entry.key]?.size,
            title: source.nodePresentations[entry.key]?.title,
            collapsed: source.nodePresentations[entry.key]?.collapsed ?? false,
            metadata: source.nodePresentations[entry.key]?.metadata ?? {},
          ),
      },
      connections: {
        for (final entry in source.connections.entries)
          edges[entry.key]!: GraphConnection(
            id: edges[entry.key]!,
            from: PortRef(
              nodeId: nodes[entry.value.from.nodeId]!,
              portId: entry.value.from.portId,
            ),
            to: PortRef(
              nodeId: nodes[entry.value.to.nodeId]!,
              portId: entry.value.to.portId,
            ),
            kind: entry.value.kind,
            data: entry.value.data,
          ),
      },
      connectionPresentations: {
        for (final entry in source.connectionPresentations.entries)
          if (edges.containsKey(entry.key))
            edges[entry.key]!: ConnectionPresentation(
              connectionId: edges[entry.key]!,
              waypoints: entry.value.waypoints
                  .map((point) => point + offset)
                  .toList(),
              label: entry.value.label,
              labelOffset: entry.value.labelOffset,
              metadata: entry.value.metadata,
            ),
      },
      frames: {
        for (final entry in source.frames.entries)
          frames[entry.key]!: GraphFrame(
            id: frames[entry.key]!,
            bounds: entry.value.bounds.translate(offset),
            title: entry.value.title,
            memberNodeIds: entry.value.memberNodeIds
                .map((id) => nodes[id])
                .whereType<String>()
                .toSet(),
            autoFit: entry.value.autoFit,
            metadata: entry.value.metadata,
          ),
      },
      comments: {
        for (final entry in source.comments.entries)
          comments[entry.key]!: GraphComment(
            id: comments[entry.key]!,
            bounds: entry.value.bounds.translate(offset),
            text: entry.value.text,
            metadata: entry.value.metadata,
          ),
      },
    );
    execute(
      MergeGraphSpaceCommand(sid, prepared, allowInvalid: true),
      label: 'Paste graph fragment',
    );
    final result = GraphSelection(
      nodes: nodes.values,
      connections: edges.values,
      frames: frames.values,
      comments: comments.values,
    );
    select(result);
    return result;
  }

  GraphSelection duplicateSelection({
    GraphPoint offset = const GraphPoint(24, 24),
    GraphIdFactory idFactory = newGraphId,
  }) => pasteGraphFragment(
    GraphFragment.capture(this),
    offset: offset,
    idFactory: idFactory,
  );
  void deleteSelection({GraphSelection? selected}) {
    final sid = activeSpaceId;
    if (sid == null) return;
    final target = selected ?? selection;
    transaction((tx) {
      tx.execute(RemoveNodesCommand(sid, target.nodes));
      tx.execute(RemoveConnectionsCommand(sid, target.connections));
      for (final id in target.frames) {
        tx.execute(RemoveFrameCommand(sid, id));
      }
      for (final id in target.comments) {
        tx.execute(RemoveCommentCommand(sid, id));
      }
    }, label: 'Delete selection');
  }

  void disconnectNode(String nodeId) {
    final sid = activeSpaceId;
    if (sid == null) return;
    execute(
      RemoveConnectionsCommand(
        sid,
        indexes[sid]?.connectionIdsByNode[nodeId] ?? {},
      ),
      label: 'Disconnect node',
    );
  }

  void moveFrameWithMembers(
    String id,
    GraphPoint delta, {
    Object? coalesceKey,
  }) {
    final sid = activeSpaceId, space = activeSpace;
    final frame = space?.frames[id];
    if (sid == null || space == null || frame == null) {
      throw StateError('Unknown frame: $id');
    }
    transaction(
      (tx) {
        tx.execute(
          UpdateFrameCommand(
            sid,
            frame.copyWith(bounds: frame.bounds.translate(delta)),
          ),
        );
        tx.execute(
          MoveNodesCommand(sid, {
            for (final id in frame.memberNodeIds)
              id:
                  (space.nodePresentations[id]?.position ?? GraphPoint.zero) +
                  delta,
          }),
        );
      },
      label: 'Move frame',
      coalesceKey: coalesceKey,
    );
  }

  String createFrameFromSelection(
    GraphRect bounds, {
    String title = 'Frame',
    GraphIdFactory idFactory = newGraphId,
  }) {
    final sid = activeSpaceId;
    if (sid == null) throw StateError('No active space.');
    final id = idFactory();
    execute(
      CreateFrameCommand(
        sid,
        GraphFrame(
          id: id,
          bounds: bounds,
          title: title,
          memberNodeIds: selection.nodes,
        ),
      ),
      label: 'Create frame',
    );
    return id;
  }

  void fitFrame(
    String id,
    Map<String, GraphRect> nodeBounds, {
    double padding = 24,
  }) {
    final sid = activeSpaceId, frame = activeSpace?.frames[id];
    if (sid == null || frame == null) throw StateError('Unknown frame: $id');
    final bounds = frame.memberNodeIds
        .map((id) => nodeBounds[id])
        .whereType<GraphRect>();
    if (bounds.isEmpty) return;
    execute(
      UpdateFrameCommand(
        sid,
        frame.copyWith(
          bounds: bounds.reduce((a, b) => a.union(b)).inflate(padding),
        ),
      ),
      label: 'Fit frame',
    );
  }

  void spliceNodeIntoConnection(
    String connectionId,
    GraphNode node, {
    NodePresentation? presentation,
    GraphIdFactory idFactory = newGraphId,
  }) {
    final sid = activeSpaceId, space = activeSpace;
    final edge = space?.connections[connectionId];
    if (sid == null || space == null || edge == null) {
      throw StateError('Unknown connection.');
    }
    transaction((tx) {
      tx.execute(AddNodeCommand(sid, node, presentation: presentation));
      final resolved = resolver.resolve(tx.document);
      final structure = resolved.structures[sid]?[node.id];
      final source = resolved.structures[sid]?[edge.from.nodeId]?.port(
        edge.from.portId,
      );
      final target = resolved.structures[sid]?[edge.to.nodeId]?.port(
        edge.to.portId,
      );
      if (structure == null || source == null || target == null) {
        throw StateError('Cannot splice unresolved ports.');
      }
      bool compatible(ResolvedPort from, ResolvedPort to) =>
          from.kind == to.kind &&
          (from.kind == GraphPortKind.control ||
              resolver.types.canConnect(
                outputType: from.dataType,
                inputType: to.dataType,
              ));
      final inputs = structure.ports.where(
        (port) =>
            port.direction == GraphPortDirection.input &&
            compatible(source, port),
      );
      final outputs = structure.ports.where(
        (port) =>
            port.direction == GraphPortDirection.output &&
            compatible(port, target),
      );
      if (inputs.isEmpty || outputs.isEmpty) {
        throw StateError('No compatible splice ports.');
      }
      tx.execute(
        ReconnectConnectionCommand(
          sid,
          connectionId,
          to: PortRef(nodeId: node.id, portId: inputs.first.id),
        ),
      );
      tx.execute(
        AddConnectionCommand(
          sid,
          GraphConnection(
            id: idFactory(),
            from: PortRef(nodeId: node.id, portId: outputs.first.id),
            to: edge.to,
            kind: edge.kind,
            data: edge.data,
          ),
        ),
      );
    }, label: 'Insert node into connection');
  }
}
