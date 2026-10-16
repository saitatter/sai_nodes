import '../geometry/geometry.dart';
import '../model/graph_document.dart';

/// A command is a pure document transform. The controller resolves and commits it.
abstract interface class GraphCommand {
  GraphDocument apply(GraphDocument document);
}

abstract base class SpaceCommand implements GraphCommand {
  const SpaceCommand(this.spaceId);
  final String spaceId;
  GraphSpace transform(GraphSpace space);
  @override
  GraphDocument apply(GraphDocument document) {
    final space = document.spaces[spaceId];
    if (space == null) throw StateError('Unknown graph space: $spaceId');
    return document.copyWith(
      spaces: {...document.spaces, spaceId: transform(space)},
    );
  }
}

/// Adds an already-remapped fragment with one map copy per entity collection.
final class MergeGraphSpaceCommand extends SpaceCommand {
  const MergeGraphSpaceCommand(
    super.spaceId,
    this.fragment, {
    this.allowInvalid = false,
  });
  final GraphSpace fragment;
  final bool allowInvalid;
  @override
  GraphSpace transform(GraphSpace space) {
    void unique(Iterable<String> existing, Iterable<String> added) {
      final ids = existing.toSet();
      for (final id in added) {
        if (ids.contains(id)) throw StateError('Duplicate graph entity: $id');
      }
    }

    unique(space.nodes.keys, fragment.nodes.keys);
    unique(space.connections.keys, fragment.connections.keys);
    unique(space.frames.keys, fragment.frames.keys);
    unique(space.comments.keys, fragment.comments.keys);
    return space.copyWith(
      nodes: {...space.nodes, ...fragment.nodes},
      connections: {...space.connections, ...fragment.connections},
      nodePresentations: {
        ...space.nodePresentations,
        ...fragment.nodePresentations,
      },
      connectionPresentations: {
        ...space.connectionPresentations,
        ...fragment.connectionPresentations,
      },
      frames: {...space.frames, ...fragment.frames},
      comments: {...space.comments, ...fragment.comments},
    );
  }
}

final class AddSpaceCommand implements GraphCommand {
  const AddSpaceCommand(this.space);
  final GraphSpace space;
  @override
  GraphDocument apply(GraphDocument document) {
    if (document.spaces.containsKey(space.id)) {
      throw StateError('Duplicate space: ${space.id}');
    }
    return document.copyWith(spaces: {...document.spaces, space.id: space});
  }
}

final class RemoveSpaceCommand implements GraphCommand {
  const RemoveSpaceCommand(this.id);
  final String id;
  @override
  GraphDocument apply(GraphDocument document) =>
      document.copyWith(spaces: {...document.spaces}..remove(id));
}

final class UpdateDocumentMetadataCommand implements GraphCommand {
  const UpdateDocumentMetadataCommand(this.metadata);
  final GraphJson metadata;
  @override
  GraphDocument apply(GraphDocument document) =>
      document.copyWith(metadata: metadata);
}

final class AddNodeCommand extends SpaceCommand {
  const AddNodeCommand(super.spaceId, this.node, {this.presentation});
  final GraphNode node;
  final NodePresentation? presentation;
  @override
  GraphSpace transform(GraphSpace space) {
    if (space.nodes.containsKey(node.id)) {
      throw StateError('Duplicate node: ${node.id}');
    }
    return space.copyWith(
      nodes: {...space.nodes, node.id: node},
      nodePresentations: {...space.nodePresentations, node.id: ?presentation},
    );
  }
}

final class RemoveNodesCommand extends SpaceCommand {
  RemoveNodesCommand(super.spaceId, Iterable<String> ids)
    : ids = Set.unmodifiable(ids);
  final Set<String> ids;
  @override
  GraphSpace transform(GraphSpace space) {
    final removedEdges = space.connections.entries
        .where(
          (entry) =>
              ids.contains(entry.value.from.nodeId) ||
              ids.contains(entry.value.to.nodeId),
        )
        .map((entry) => entry.key)
        .toSet();
    return space.copyWith(
      nodes: {...space.nodes}..removeWhere((id, _) => ids.contains(id)),
      nodePresentations: {...space.nodePresentations}
        ..removeWhere((id, _) => ids.contains(id)),
      connections: {...space.connections}
        ..removeWhere((id, _) => removedEdges.contains(id)),
      connectionPresentations: {...space.connectionPresentations}
        ..removeWhere((id, _) => removedEdges.contains(id)),
      frames: space.frames.map(
        (id, frame) => MapEntry(
          id,
          frame.copyWith(
            memberNodeIds: {...frame.memberNodeIds}..removeAll(ids),
          ),
        ),
      ),
    );
  }
}

final class UpdateNodeDataCommand extends SpaceCommand {
  const UpdateNodeDataCommand(
    super.spaceId,
    this.nodeId,
    this.data, {
    this.merge = false,
  });
  final String nodeId;
  final GraphJson data;
  final bool merge;
  @override
  GraphSpace transform(GraphSpace space) {
    final node = space.nodes[nodeId];
    if (node == null) throw StateError('Unknown node: $nodeId');
    return space.copyWith(
      nodes: {
        ...space.nodes,
        nodeId: node.copyWith(data: merge ? {...node.data, ...data} : data),
      },
    );
  }
}

final class ReplaceNodeTypeCommand extends SpaceCommand {
  const ReplaceNodeTypeCommand(
    super.spaceId,
    this.nodeId,
    this.type, {
    this.data,
  });
  final String nodeId;
  final String type;
  final GraphJson? data;
  @override
  GraphSpace transform(GraphSpace space) {
    final node = space.nodes[nodeId];
    if (node == null) throw StateError('Unknown node: $nodeId');
    return space.copyWith(
      nodes: {
        ...space.nodes,
        nodeId: node.copyWith(type: type, data: data),
      },
    );
  }
}

final class UpdateNodePresentationCommand extends SpaceCommand {
  const UpdateNodePresentationCommand(super.spaceId, this.presentation);
  final NodePresentation presentation;
  @override
  GraphSpace transform(GraphSpace space) => space.copyWith(
    nodePresentations: {
      ...space.nodePresentations,
      presentation.nodeId: presentation,
    },
  );
}

final class MoveNodesCommand extends SpaceCommand {
  MoveNodesCommand(super.spaceId, Map<String, GraphPoint> positions)
    : positions = Map.unmodifiable(positions);
  final Map<String, GraphPoint> positions;
  @override
  GraphSpace transform(GraphSpace space) => space.copyWith(
    nodePresentations: {
      ...space.nodePresentations,
      for (final entry in positions.entries)
        entry.key:
            (space.nodePresentations[entry.key] ??
                    NodePresentation(
                      nodeId: entry.key,
                      position: GraphPoint.zero,
                    ))
                .copyWith(position: entry.value),
    },
  );
}

final class ResizeNodesCommand extends SpaceCommand {
  ResizeNodesCommand(super.spaceId, Map<String, GraphSize> sizes)
    : sizes = Map.unmodifiable(sizes);
  final Map<String, GraphSize> sizes;
  @override
  GraphSpace transform(GraphSpace space) => space.copyWith(
    nodePresentations: {
      ...space.nodePresentations,
      for (final entry in sizes.entries)
        entry.key:
            (space.nodePresentations[entry.key] ??
                    NodePresentation(
                      nodeId: entry.key,
                      position: GraphPoint.zero,
                    ))
                .copyWith(size: entry.value),
    },
  );
}

final class SetNodeTitleCommand extends SpaceCommand {
  const SetNodeTitleCommand(super.spaceId, this.nodeId, this.title);
  final String nodeId;
  final String? title;
  @override
  GraphSpace transform(GraphSpace space) => UpdateNodePresentationCommand(
    spaceId,
    (space.nodePresentations[nodeId] ??
            NodePresentation(nodeId: nodeId, position: GraphPoint.zero))
        .copyWith(title: title),
  ).transform(space);
}

final class SetNodeCollapsedCommand extends SpaceCommand {
  const SetNodeCollapsedCommand(super.spaceId, this.nodeId, this.collapsed);
  final String nodeId;
  final bool collapsed;
  @override
  GraphSpace transform(GraphSpace space) => UpdateNodePresentationCommand(
    spaceId,
    (space.nodePresentations[nodeId] ??
            NodePresentation(nodeId: nodeId, position: GraphPoint.zero))
        .copyWith(collapsed: collapsed),
  ).transform(space);
}

final class AddConnectionCommand extends SpaceCommand {
  const AddConnectionCommand(
    super.spaceId,
    this.connection, {
    this.allowInvalid = false,
  });
  final GraphConnection connection;
  final bool allowInvalid;
  @override
  GraphSpace transform(GraphSpace space) {
    if (space.connections.containsKey(connection.id)) {
      throw StateError('Duplicate connection: ${connection.id}');
    }
    return space.copyWith(
      connections: {...space.connections, connection.id: connection},
    );
  }
}

final class RemoveConnectionsCommand extends SpaceCommand {
  RemoveConnectionsCommand(super.spaceId, Iterable<String> ids)
    : ids = Set.unmodifiable(ids);
  final Set<String> ids;
  @override
  GraphSpace transform(GraphSpace space) => space.copyWith(
    connections: {...space.connections}
      ..removeWhere((id, _) => ids.contains(id)),
    connectionPresentations: {...space.connectionPresentations}
      ..removeWhere((id, _) => ids.contains(id)),
  );
}

final class ReconnectConnectionCommand extends SpaceCommand {
  const ReconnectConnectionCommand(
    super.spaceId,
    this.connectionId, {
    this.from,
    this.to,
  });
  final String connectionId;
  final PortRef? from;
  final PortRef? to;
  @override
  GraphSpace transform(GraphSpace space) {
    final connection = space.connections[connectionId];
    if (connection == null) {
      throw StateError('Unknown connection: $connectionId');
    }
    return space.copyWith(
      connections: {
        ...space.connections,
        connectionId: connection.copyWith(from: from, to: to),
      },
    );
  }
}

final class UpdateConnectionPresentationCommand extends SpaceCommand {
  const UpdateConnectionPresentationCommand(super.spaceId, this.presentation);
  final ConnectionPresentation presentation;
  @override
  GraphSpace transform(GraphSpace space) => space.copyWith(
    connectionPresentations: {
      ...space.connectionPresentations,
      presentation.connectionId: presentation,
    },
  );
}

final class CreateFrameCommand extends SpaceCommand {
  const CreateFrameCommand(super.spaceId, this.frame);
  final GraphFrame frame;
  @override
  GraphSpace transform(GraphSpace space) {
    if (space.frames.containsKey(frame.id)) {
      throw StateError('Duplicate frame: ${frame.id}');
    }
    return space.copyWith(frames: {...space.frames, frame.id: frame});
  }
}

final class UpdateFrameCommand extends SpaceCommand {
  const UpdateFrameCommand(super.spaceId, this.frame);
  final GraphFrame frame;
  @override
  GraphSpace transform(GraphSpace space) {
    if (!space.frames.containsKey(frame.id)) {
      throw StateError('Unknown frame: ${frame.id}');
    }
    return space.copyWith(frames: {...space.frames, frame.id: frame});
  }
}

final class RemoveFrameCommand extends SpaceCommand {
  const RemoveFrameCommand(
    super.spaceId,
    this.id, {
    this.removeMembers = false,
  });
  final String id;
  final bool removeMembers;
  @override
  GraphSpace transform(GraphSpace space) {
    final members = space.frames[id]?.memberNodeIds ?? {};
    final next = space.copyWith(frames: {...space.frames}..remove(id));
    return removeMembers
        ? RemoveNodesCommand(spaceId, members).transform(next)
        : next;
  }
}

final class CreateCommentCommand extends SpaceCommand {
  const CreateCommentCommand(super.spaceId, this.comment);
  final GraphComment comment;
  @override
  GraphSpace transform(GraphSpace space) {
    if (space.comments.containsKey(comment.id)) {
      throw StateError('Duplicate comment: ${comment.id}');
    }
    return space.copyWith(comments: {...space.comments, comment.id: comment});
  }
}

final class UpdateCommentCommand extends SpaceCommand {
  const UpdateCommentCommand(super.spaceId, this.comment);
  final GraphComment comment;
  @override
  GraphSpace transform(GraphSpace space) {
    if (!space.comments.containsKey(comment.id)) {
      throw StateError('Unknown comment: ${comment.id}');
    }
    return space.copyWith(comments: {...space.comments, comment.id: comment});
  }
}

final class RemoveCommentCommand extends SpaceCommand {
  const RemoveCommentCommand(super.spaceId, this.id);
  final String id;
  @override
  GraphSpace transform(GraphSpace space) =>
      space.copyWith(comments: {...space.comments}..remove(id));
}
