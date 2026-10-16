import '../model/immutable_json.dart';

enum GraphExecutionStatus { idle, queued, running, completed, aborted, error }

final class ScopedNodeRef {
  const ScopedNodeRef(this.spaceId, this.nodeId);
  final String spaceId, nodeId;
  @override
  bool operator ==(Object other) =>
      other is ScopedNodeRef &&
      spaceId == other.spaceId &&
      nodeId == other.nodeId;
  @override
  int get hashCode => Object.hash(spaceId, nodeId);
}

final class ScopedConnectionRef {
  const ScopedConnectionRef(this.spaceId, this.connectionId);
  final String spaceId, connectionId;
  @override
  bool operator ==(Object other) =>
      other is ScopedConnectionRef &&
      spaceId == other.spaceId &&
      connectionId == other.connectionId;
  @override
  int get hashCode => Object.hash(spaceId, connectionId);
}

final class NodeExecutionVisual {
  NodeExecutionVisual({
    this.status = GraphExecutionStatus.idle,
    this.activeCount = 0,
    this.invocationCount = 0,
    this.duration = Duration.zero,
    this.error,
    GraphJson metadata = const {},
  }) : metadata = freezeJson(metadata);
  final GraphExecutionStatus status;
  final int activeCount, invocationCount;
  final Duration duration;
  final String? error;
  final GraphJson metadata;
}

final class ConnectionExecutionVisual {
  const ConnectionExecutionVisual({
    this.active = false,
    this.traversalCount = 0,
  });
  final bool active;
  final int traversalCount;
}

final class GraphExecutionSnapshot {
  GraphExecutionSnapshot({
    Map<ScopedNodeRef, NodeExecutionVisual> nodes = const {},
    Map<ScopedConnectionRef, ConnectionExecutionVisual> connections = const {},
    this.executionId,
  }) : nodes = Map.unmodifiable(nodes),
       connections = Map.unmodifiable(connections);
  final Map<ScopedNodeRef, NodeExecutionVisual> nodes;
  final Map<ScopedConnectionRef, ConnectionExecutionVisual> connections;
  final String? executionId;
}

abstract interface class GraphExecutionVisualSource {
  GraphExecutionSnapshot get snapshot;
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}

/// Accepts live, retained, remote or synthetic snapshots without executing nodes.
final class GraphExecutionVisualController
    implements GraphExecutionVisualSource {
  GraphExecutionSnapshot _snapshot = GraphExecutionSnapshot();
  final Set<void Function()> _listeners = {};
  @override
  GraphExecutionSnapshot get snapshot => _snapshot;
  void apply(GraphExecutionSnapshot snapshot) {
    _snapshot = snapshot;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void clear() => apply(GraphExecutionSnapshot());
  @override
  void addListener(void Function() listener) => _listeners.add(listener);
  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void dispose() => _listeners.clear();
}
