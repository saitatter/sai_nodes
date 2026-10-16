import 'dart:convert';
import 'dart:math';

import '../commands/graph_commands.dart';
import '../controller/graph_controller.dart';
import '../definitions/node_definition.dart';
import '../geometry/geometry.dart';
import '../model/graph_document.dart';
import '../model/immutable_json.dart';

typedef GraphIdFactory = String Function();
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
  GraphSelection pasteGraphFragment(
    GraphFragment fragment, {
    GraphPoint offset = const GraphPoint(24, 24),
    GraphIdFactory idFactory = newGraphId,
    GraphFragment Function(GraphFragment)? enrich,
  }) {
    final source = (enrich?.call(fragment) ?? fragment).space;
    final sid = activeSpaceId;
    if (sid == null) throw StateError('No active space.');
    final nodes = {for (final id in source.nodes.keys) id: idFactory()};
    final edges = {for (final id in source.connections.keys) id: idFactory()};
    final frames = {for (final id in source.frames.keys) id: idFactory()};
    final comments = {for (final id in source.comments.keys) id: idFactory()};
    transaction((tx) {
      for (final entry in source.nodes.entries) {
        final node = entry.value, view = source.nodePresentations[entry.key];
        tx.execute(
          AddNodeCommand(
            sid,
            GraphNode(
              id: nodes[entry.key]!,
              type: node.type,
              data: node.data,
              metadata: node.metadata,
            ),
            presentation: NodePresentation(
              nodeId: nodes[entry.key]!,
              position: (view?.position ?? GraphPoint.zero) + offset,
              size: view?.size,
              title: view?.title,
              collapsed: view?.collapsed ?? false,
              metadata: view?.metadata ?? {},
            ),
          ),
        );
      }
      for (final entry in source.connections.entries) {
        final edge = entry.value;
        if (!nodes.containsKey(edge.from.nodeId) ||
            !nodes.containsKey(edge.to.nodeId)) {
          throw const FormatException(
            'Fragment contains an external connection endpoint.',
          );
        }
        final id = edges[entry.key]!;
        tx.execute(
          AddConnectionCommand(
            sid,
            GraphConnection(
              id: id,
              from: PortRef(
                nodeId: nodes[edge.from.nodeId]!,
                portId: edge.from.portId,
              ),
              to: PortRef(
                nodeId: nodes[edge.to.nodeId]!,
                portId: edge.to.portId,
              ),
              kind: edge.kind,
              data: edge.data,
            ),
            allowInvalid: true,
          ),
        );
        final view = source.connectionPresentations[entry.key];
        if (view != null) {
          tx.execute(
            UpdateConnectionPresentationCommand(
              sid,
              ConnectionPresentation(
                connectionId: id,
                waypoints: view.waypoints
                    .map((point) => point + offset)
                    .toList(),
                label: view.label,
                labelOffset: view.labelOffset,
                metadata: view.metadata,
              ),
            ),
          );
        }
      }
      for (final entry in source.frames.entries) {
        final frame = entry.value;
        tx.execute(
          CreateFrameCommand(
            sid,
            GraphFrame(
              id: frames[entry.key]!,
              bounds: frame.bounds.translate(offset),
              title: frame.title,
              memberNodeIds: frame.memberNodeIds
                  .map((id) => nodes[id])
                  .whereType<String>()
                  .toSet(),
              autoFit: frame.autoFit,
              metadata: frame.metadata,
            ),
          ),
        );
      }
      for (final entry in source.comments.entries) {
        final comment = entry.value;
        tx.execute(
          CreateCommentCommand(
            sid,
            GraphComment(
              id: comments[entry.key]!,
              bounds: comment.bounds.translate(offset),
              text: comment.text,
              metadata: comment.metadata,
            ),
          ),
        );
      }
    }, label: 'Paste graph fragment');
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
  void deleteSelection() {
    final sid = activeSpaceId;
    if (sid == null) return;
    final selected = selection;
    transaction((tx) {
      tx.execute(RemoveNodesCommand(sid, selected.nodes));
      tx.execute(RemoveConnectionsCommand(sid, selected.connections));
      for (final id in selected.frames) {
        tx.execute(RemoveFrameCommand(sid, id));
      }
      for (final id in selected.comments) {
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
