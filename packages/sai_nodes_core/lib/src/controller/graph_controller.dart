import 'package:collection/collection.dart';

import '../commands/graph_commands.dart';
import '../diagnostics/graph_diagnostic.dart';
import '../geometry/geometry.dart';
import '../indexing/graph_indexes.dart';
import '../model/graph_document.dart';
import '../resolution/graph_resolver.dart';

final class GraphChangeSet {
  GraphChangeSet._({
    required Set<String> addedNodeIds,
    required Set<String> removedNodeIds,
    required Set<String> updatedNodeIds,
    required Set<String> addedConnectionIds,
    required Set<String> removedConnectionIds,
    required Set<String> updatedConnectionIds,
    required Set<String> updatedFrameIds,
    required Set<String> updatedCommentIds,
    required Set<String> updatedSpaceIds,
    required this.semanticChanged,
    required this.presentationChanged,
  }) : addedNodeIds = Set.unmodifiable(addedNodeIds),
       removedNodeIds = Set.unmodifiable(removedNodeIds),
       updatedNodeIds = Set.unmodifiable(updatedNodeIds),
       addedConnectionIds = Set.unmodifiable(addedConnectionIds),
       removedConnectionIds = Set.unmodifiable(removedConnectionIds),
       updatedConnectionIds = Set.unmodifiable(updatedConnectionIds),
       updatedFrameIds = Set.unmodifiable(updatedFrameIds),
       updatedCommentIds = Set.unmodifiable(updatedCommentIds),
       updatedSpaceIds = Set.unmodifiable(updatedSpaceIds);
  final Set<String> addedNodeIds, removedNodeIds, updatedNodeIds;
  final Set<String> addedConnectionIds,
      removedConnectionIds,
      updatedConnectionIds;
  final Set<String> updatedFrameIds, updatedCommentIds, updatedSpaceIds;
  final bool semanticChanged, presentationChanged;
  factory GraphChangeSet.between(GraphDocument before, GraphDocument after) {
    final addedNodes = <String>{},
        removedNodes = <String>{},
        updatedNodes = <String>{};
    final addedEdges = <String>{},
        removedEdges = <String>{},
        updatedEdges = <String>{};
    final frames = <String>{}, comments = <String>{}, spaces = <String>{};
    var semantic = !const DeepCollectionEquality().equals(
      before.metadata,
      after.metadata,
    );
    var presentation = false;
    void compare<T>(
      Map<String, T> a,
      Map<String, T> b,
      Set<String> added,
      Set<String> removed,
      Set<String> updated,
    ) {
      added.addAll(b.keys.where((id) => !a.containsKey(id)));
      removed.addAll(a.keys.where((id) => !b.containsKey(id)));
      updated.addAll(a.keys.where((id) => b.containsKey(id) && a[id] != b[id]));
    }

    for (final sid in {...before.spaces.keys, ...after.spaces.keys}) {
      final a = before.spaces[sid] ?? GraphSpace(id: sid);
      final b = after.spaces[sid] ?? GraphSpace(id: sid);
      if (a == b &&
          before.spaces.containsKey(sid) == after.spaces.containsKey(sid)) {
        continue;
      }
      spaces.add(sid);
      compare(a.nodes, b.nodes, addedNodes, removedNodes, updatedNodes);
      compare(
        a.connections,
        b.connections,
        addedEdges,
        removedEdges,
        updatedEdges,
      );
      final changedFrames = {
        ...a.frames.keys,
        ...b.frames.keys,
      }.where((id) => a.frames[id] != b.frames[id]);
      final changedComments = {
        ...a.comments.keys,
        ...b.comments.keys,
      }.where((id) => a.comments[id] != b.comments[id]);
      frames.addAll(changedFrames);
      comments.addAll(changedComments);
      semantic =
          semantic ||
          !const DeepCollectionEquality().equals(a.nodes, b.nodes) ||
          !const DeepCollectionEquality().equals(
            a.connections,
            b.connections,
          ) ||
          !const DeepCollectionEquality().equals(a.metadata, b.metadata) ||
          before.spaces.containsKey(sid) != after.spaces.containsKey(sid);
      final moved = {...a.nodePresentations.keys, ...b.nodePresentations.keys}
          .where((id) => a.nodePresentations[id] != b.nodePresentations[id])
          .toSet();
      updatedNodes.addAll(
        moved.difference(addedNodes).difference(removedNodes),
      );
      final routed =
          {...a.connectionPresentations.keys, ...b.connectionPresentations.keys}
              .where(
                (id) =>
                    a.connectionPresentations[id] !=
                    b.connectionPresentations[id],
              )
              .toSet();
      updatedEdges.addAll(
        routed.difference(addedEdges).difference(removedEdges),
      );
      presentation =
          presentation ||
          moved.isNotEmpty ||
          routed.isNotEmpty ||
          changedFrames.isNotEmpty ||
          changedComments.isNotEmpty;
    }
    return GraphChangeSet._(
      addedNodeIds: addedNodes,
      removedNodeIds: removedNodes,
      updatedNodeIds: updatedNodes,
      addedConnectionIds: addedEdges,
      removedConnectionIds: removedEdges,
      updatedConnectionIds: updatedEdges,
      updatedFrameIds: frames,
      updatedCommentIds: comments,
      updatedSpaceIds: spaces,
      semanticChanged: semantic,
      presentationChanged: presentation,
    );
  }
}

final class GraphDocumentChange {
  const GraphDocumentChange({
    required this.label,
    required this.revision,
    required this.semanticRevision,
    required this.changes,
  });
  final String label;
  final int revision, semanticRevision;
  final GraphChangeSet changes;
}

final class GraphMutationException implements Exception {
  GraphMutationException(this.message, Iterable<GraphDiagnostic> diagnostics)
    : diagnostics = List.unmodifiable(diagnostics);
  final String message;
  final List<GraphDiagnostic> diagnostics;
  @override
  String toString() =>
      '$message: ${diagnostics.map((issue) => issue.code).join(', ')}';
}

final class GraphTransaction {
  GraphTransaction._(this._document);
  GraphDocument _document;
  GraphDocument get document => _document;
  final Set<(String, String)> _strictConnections = {};
  bool _closed = false;
  void execute(GraphCommand command) {
    if (_closed) throw StateError('Transaction has already finished.');
    _document = command.apply(_document);
    if (command is AddConnectionCommand && !command.allowInvalid) {
      _strictConnections.add((command.spaceId, command.connection.id));
    }
    if (command is ReconnectConnectionCommand) {
      _strictConnections.add((command.spaceId, command.connectionId));
    }
  }
}

final class _HistoryEntry {
  _HistoryEntry(
    this.before,
    this.after,
    this.beforeRevision,
    this.afterRevision,
    this.beforeSemantic,
    this.afterSemantic,
    this.label,
    this.coalesceKey,
  );
  final GraphDocument before;
  GraphDocument after;
  final int beforeRevision, beforeSemantic;
  int afterRevision, afterSemantic;
  String label;
  final Object? coalesceKey;
}

final class GraphSelection {
  GraphSelection({
    Iterable<String> nodes = const [],
    Iterable<String> connections = const [],
    Iterable<String> frames = const [],
    Iterable<String> comments = const [],
  }) : nodes = Set.unmodifiable(nodes),
       connections = Set.unmodifiable(connections),
       frames = Set.unmodifiable(frames),
       comments = Set.unmodifiable(comments);
  final Set<String> nodes, connections, frames, comments;
  bool get isEmpty =>
      nodes.isEmpty &&
      connections.isEmpty &&
      frames.isEmpty &&
      comments.isEmpty;
}

final class GraphCamera {
  const GraphCamera({this.offset = GraphPoint.zero, this.zoom = 1});
  final GraphPoint offset;
  final double zoom;
  GraphPoint worldToViewport(GraphPoint point) => point.scale(zoom) + offset;
  GraphPoint viewportToWorld(GraphPoint point) =>
      (point - offset).scale(1 / zoom);
  GraphCamera pan(GraphPoint delta) =>
      GraphCamera(offset: offset + delta, zoom: zoom);
  GraphCamera zoomAt(
    GraphPoint anchor,
    double factor, {
    double minZoom = .1,
    double maxZoom = 4,
  }) {
    if (!factor.isFinite || factor <= 0) {
      throw ArgumentError.value(factor, 'factor');
    }
    final next = (zoom * factor).clamp(minZoom, maxZoom);
    return GraphCamera(
      offset: anchor - viewportToWorld(anchor).scale(next),
      zoom: next,
    );
  }

  GraphCamera focusBounds(
    GraphRect bounds,
    GraphSize viewport, {
    double padding = 40,
  }) {
    if (!bounds.isValid || !viewport.isValid) {
      throw ArgumentError('Invalid focus bounds.');
    }
    final width = (viewport.width - 2 * padding).clamp(1, double.infinity);
    final height = (viewport.height - 2 * padding).clamp(1, double.infinity);
    final x = width / (bounds.width == 0 ? 1 : bounds.width);
    final y = height / (bounds.height == 0 ? 1 : bounds.height);
    final next = (x < y ? x : y).clamp(.1, 4.0);
    return GraphCamera(
      offset:
          GraphPoint(viewport.width / 2, viewport.height / 2) -
          bounds.center.scale(next),
      zoom: next,
    );
  }
}

/// Synchronous single-owner authoring engine. All persistent edits commit here.
final class GraphController {
  GraphController({
    required GraphDocument document,
    required this.resolver,
    String? activeSpaceId,
    this.historyCapacity = 100,
  }) : _document = document,
       _activeSpaceId = activeSpaceId ?? document.spaces.keys.firstOrNull {
    if (historyCapacity < 0) {
      throw ArgumentError.value(historyCapacity, 'historyCapacity');
    }
    _resolution = resolver.resolve(document);
    _document = _resolution.document;
    _rebuildIndexes();
    resolver.definitions.addListener(_definitionsChanged);
  }
  final GraphResolver resolver;
  final int historyCapacity;
  GraphDocument _document;
  late GraphResolution _resolution;
  Map<String, GraphIndexes> _indexes = {};
  String? _activeSpaceId;
  GraphSelection _selection = GraphSelection();
  GraphCamera _camera = const GraphCamera();
  final List<_HistoryEntry> _undo = [], _redo = [];
  final Set<void Function()> _listeners = {};
  final Set<void Function(GraphDocumentChange)> _documentListeners = {};
  int _revision = 0, _semanticRevision = 0, _sequence = 0, _savedRevision = 0;
  bool _busy = false, _disposed = false;
  GraphDocument get document => _document;
  GraphResolution get resolution => _resolution;
  Map<String, GraphIndexes> get indexes => Map.unmodifiable(_indexes);
  String? get activeSpaceId => _activeSpaceId;
  GraphSpace? get activeSpace => _document.spaces[_activeSpaceId];
  GraphSelection get selection => _selection;
  GraphCamera get camera => _camera;
  int get revision => _revision;
  int get semanticRevision => _semanticRevision;
  bool get isDirty => _revision != _savedRevision;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoCount => _undo.length;
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void addDocumentListener(void Function(GraphDocumentChange) listener) =>
      _documentListeners.add(listener);
  void removeDocumentListener(void Function(GraphDocumentChange) listener) =>
      _documentListeners.remove(listener);
  void _check() {
    if (_disposed) throw StateError('Graph controller is disposed.');
    if (_busy) throw StateError('Nested mutations are not permitted.');
  }

  void execute(
    GraphCommand command, {
    String label = 'Edit graph',
    Object? coalesceKey,
  }) => transaction(
    (tx) => tx.execute(command),
    label: label,
    coalesceKey: coalesceKey,
  );
  void transaction(
    void Function(GraphTransaction) operation, {
    required String label,
    Object? coalesceKey,
  }) {
    _check();
    _busy = true;
    final tx = GraphTransaction._(_document);
    try {
      operation(tx);
      final result = resolver.resolve(tx.document);
      final baseline = _resolution.diagnostics.map(_issueKey).toSet();
      const structural = {
        'empty-id',
        'identity-mismatch',
        'duplicate-id',
        'empty-node-type',
        'invalid-geometry',
        'invalid-waypoint',
        'invalid-presentation-reference',
        'invalid-frame-member',
      };
      final rejected = result.diagnostics.where(
        (issue) =>
            issue.code == 'non-converging-definition' ||
            (!baseline.contains(_issueKey(issue)) &&
                (structural.contains(issue.code) ||
                    issue.code == 'resolution-error')) ||
            (issue.kind == GraphEntityKind.connection &&
                tx._strictConnections.contains((
                  issue.spaceId,
                  issue.entityId,
                ))),
      );
      if (rejected.isNotEmpty) {
        throw GraphMutationException('Transaction rejected', rejected);
      }
      if (result.document == _document) return;
      final before = _document;
      final beforeRevision = _revision, beforeSemantic = _semanticRevision;
      final changes = GraphChangeSet.between(before, result.document);
      _revision = ++_sequence;
      if (changes.semanticChanged) _semanticRevision = _revision;
      _document = result.document;
      _resolution = result;
      _rebuildIndexes();
      _reconcileEphemeral();
      if (historyCapacity > 0) {
        if (coalesceKey != null &&
            _undo.isNotEmpty &&
            _undo.last.coalesceKey == coalesceKey &&
            _redo.isEmpty &&
            _undo.last.afterRevision != _savedRevision) {
          final entry = _undo.last;
          entry.after = _document;
          entry.afterRevision = _revision;
          entry.afterSemantic = _semanticRevision;
          entry.label = label;
        } else {
          _undo.add(
            _HistoryEntry(
              before,
              _document,
              beforeRevision,
              _revision,
              beforeSemantic,
              _semanticRevision,
              label,
              coalesceKey,
            ),
          );
          if (_undo.length > historyCapacity) _undo.removeAt(0);
        }
      }
      _redo.clear();
      _notify(
        GraphDocumentChange(
          label: label,
          revision: _revision,
          semanticRevision: _semanticRevision,
          changes: changes,
        ),
      );
    } finally {
      tx._closed = true;
      _busy = false;
    }
  }

  String _issueKey(GraphDiagnostic issue) =>
      '${issue.code}/${issue.spaceId}/${issue.kind}/${issue.entityId}/${issue.portId}';
  void _rebuildIndexes() {
    _indexes = {
      for (final space in _document.spaces.values)
        space.id:
            _indexes[space.id]?.updatedFor(space) ??
            GraphIndexes.fromSpace(space),
    };
  }

  void _reconcileEphemeral() {
    if (!_document.spaces.containsKey(_activeSpaceId)) {
      _activeSpaceId = _document.spaces.keys.firstOrNull;
    }
    final space = activeSpace;
    _selection = GraphSelection(
      nodes: _selection.nodes.where(
        (id) => space?.nodes.containsKey(id) == true,
      ),
      connections: _selection.connections.where(
        (id) => space?.connections.containsKey(id) == true,
      ),
      frames: _selection.frames.where(
        (id) => space?.frames.containsKey(id) == true,
      ),
      comments: _selection.comments.where(
        (id) => space?.comments.containsKey(id) == true,
      ),
    );
  }

  void _definitionsChanged() {
    _check();
    final result = resolver.resolve(_document);
    if (result.document != _document) {
      throw StateError(
        'Registry refresh cannot silently mutate a document; use preserve policy.',
      );
    }
    _resolution = result;
    _notify();
  }

  void _notify([GraphDocumentChange? change]) {
    if (change != null) {
      for (final listener in List.of(_documentListeners)) {
        listener(change);
      }
    }
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void setActiveSpace(String id) {
    _check();
    if (!_document.spaces.containsKey(id)) {
      throw StateError('Unknown space: $id');
    }
    _activeSpaceId = id;
    _selection = GraphSelection();
    _notify();
  }

  void select(GraphSelection value) {
    _check();
    _selection = value;
    _reconcileEphemeral();
    _notify();
  }

  void selectAll() => select(
    GraphSelection(
      nodes: activeSpace?.nodes.keys ?? [],
      frames: activeSpace?.frames.keys ?? [],
      comments: activeSpace?.comments.keys ?? [],
    ),
  );
  void toggleNode(String id) {
    final nodes = {...selection.nodes};
    if (!nodes.remove(id)) nodes.add(id);
    select(GraphSelection(nodes: nodes));
  }

  void marquee(
    GraphRect bounds,
    Map<String, GraphRect> nodeBounds, {
    bool additive = false,
  }) => select(
    GraphSelection(
      nodes: {
        if (additive) ...selection.nodes,
        for (final entry in nodeBounds.entries)
          if (bounds.overlaps(entry.value)) entry.key,
      },
    ),
  );
  void focusNodes(
    Iterable<String> ids,
    Map<String, GraphRect> nodeBounds,
    GraphSize viewport,
  ) {
    final bounds = ids.map((id) => nodeBounds[id]).whereType<GraphRect>();
    if (bounds.isNotEmpty)
      setCamera(
        camera.focusBounds(bounds.reduce((a, b) => a.union(b)), viewport),
      );
  }

  void fitSpace(Map<String, GraphRect> nodeBounds, GraphSize viewport) =>
      focusNodes(nodeBounds.keys, nodeBounds, viewport);
  void setCamera(GraphCamera value) {
    _check();
    if (!value.offset.isFinite || !value.zoom.isFinite || value.zoom <= 0) {
      throw ArgumentError('Invalid camera.');
    }
    _camera = value;
    _notify();
  }

  void markSaved() {
    _check();
    _savedRevision = _revision;
    _notify();
  }

  void clearHistory() {
    _check();
    _undo.clear();
    _redo.clear();
    _notify();
  }

  void undo() => _restore(undo: true);
  void redo() => _restore(undo: false);
  void _restore({required bool undo}) {
    _check();
    final source = undo ? _undo : _redo, target = undo ? _redo : _undo;
    if (source.isEmpty) return;
    final entry = source.last;
    final next = undo ? entry.before : entry.after;
    final resolved = resolver.resolve(next);
    if (!resolved.converged) {
      throw GraphMutationException(
        'History resolution failed',
        resolved.diagnostics,
      );
    }
    final changes = GraphChangeSet.between(_document, resolved.document);
    source.removeLast();
    target.add(entry);
    _document = resolved.document;
    _resolution = resolved;
    _revision = undo ? entry.beforeRevision : entry.afterRevision;
    _semanticRevision = undo ? entry.beforeSemantic : entry.afterSemantic;
    _rebuildIndexes();
    _reconcileEphemeral();
    _busy = true;
    try {
      _notify(
        GraphDocumentChange(
          label: '${undo ? 'Undo' : 'Redo'} ${entry.label}',
          revision: _revision,
          semanticRevision: _semanticRevision,
          changes: changes,
        ),
      );
    } finally {
      _busy = false;
    }
  }

  void replaceDocument(GraphDocument document, {bool markSaved = true}) {
    _check();
    final resolved = resolver.resolve(document);
    if (!resolved.converged) {
      throw GraphMutationException('Load failed', resolved.diagnostics);
    }
    final changes = GraphChangeSet.between(_document, resolved.document);
    _document = resolved.document;
    _resolution = resolved;
    _revision = ++_sequence;
    _semanticRevision = _revision;
    if (markSaved) _savedRevision = _revision;
    _undo.clear();
    _redo.clear();
    _selection = GraphSelection();
    _rebuildIndexes();
    _reconcileEphemeral();
    _busy = true;
    try {
      _notify(
        GraphDocumentChange(
          label: 'Replace document',
          revision: _revision,
          semanticRevision: _semanticRevision,
          changes: changes,
        ),
      );
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    resolver.definitions.removeListener(_definitionsChanged);
    _listeners.clear();
    _documentListeners.clear();
    _disposed = true;
  }
}
