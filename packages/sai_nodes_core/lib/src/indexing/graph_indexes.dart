import '../model/graph_document.dart';

/// Rebuildable adjacency caches. No index is written into the document.
final class GraphIndexes {
  GraphIndexes._(
    this._connections,
    this.connectionIdsByNode,
    this.connectionIdsByPort,
    this.incomingConnectionIds,
    this.outgoingConnectionIds,
  );
  factory GraphIndexes.fromSpace(GraphSpace space) {
    final byNode = <String, Set<String>>{};
    final byPort = <PortRef, Set<String>>{};
    final incoming = <String, Set<String>>{};
    final outgoing = <String, Set<String>>{};
    for (final entry in space.connections.entries) {
      final edge = entry.value;
      for (final endpoint in [edge.from, edge.to]) {
        (byNode[endpoint.nodeId] ??= {}).add(entry.key);
        (byPort[endpoint] ??= {}).add(entry.key);
      }
      (incoming[edge.to.nodeId] ??= {}).add(entry.key);
      (outgoing[edge.from.nodeId] ??= {}).add(entry.key);
    }
    return GraphIndexes._(
      space.connections,
      _freeze(byNode),
      _freeze(byPort),
      _freeze(incoming),
      _freeze(outgoing),
    );
  }
  final Map<String, Set<String>> connectionIdsByNode;
  final Map<PortRef, Set<String>> connectionIdsByPort;
  final Map<String, Set<String>> incomingConnectionIds;
  final Map<String, Set<String>> outgoingConnectionIds;
  final Map<String, GraphConnection> _connections;

  /// Produces a detached cache by reconciling changed connection IDs only.
  /// The previous cache remains valid for its immutable document snapshot.
  GraphIndexes updatedFor(GraphSpace space) {
    final byNode = _copy(connectionIdsByNode);
    final byPort = _copy(connectionIdsByPort);
    final incoming = _copy(incomingConnectionIds);
    final outgoing = _copy(outgoingConnectionIds);
    void update(String id, GraphConnection edge, {required bool add}) {
      void touch<K>(Map<K, Set<String>> map, K key) {
        if (add) {
          (map[key] ??= {}).add(id);
        } else {
          map[key]?.remove(id);
          if (map[key]?.isEmpty == true) map.remove(key);
        }
      }

      for (final endpoint in [edge.from, edge.to]) {
        touch(byNode, endpoint.nodeId);
        touch(byPort, endpoint);
      }
      touch(incoming, edge.to.nodeId);
      touch(outgoing, edge.from.nodeId);
    }

    for (final entry in _connections.entries) {
      if (space.connections[entry.key] != entry.value) {
        update(entry.key, entry.value, add: false);
      }
    }
    for (final entry in space.connections.entries) {
      if (_connections[entry.key] != entry.value) {
        update(entry.key, entry.value, add: true);
      }
    }
    return GraphIndexes._(
      space.connections,
      _freeze(byNode),
      _freeze(byPort),
      _freeze(incoming),
      _freeze(outgoing),
    );
  }

  static Map<K, Set<String>> _copy<K>(Map<K, Set<String>> map) =>
      map.map((key, value) => MapEntry(key, {...value}));
  static Map<K, Set<String>> _freeze<K>(Map<K, Set<String>> map) =>
      Map.unmodifiable(
        map.map((key, value) => MapEntry(key, Set<String>.unmodifiable(value))),
      );
}
