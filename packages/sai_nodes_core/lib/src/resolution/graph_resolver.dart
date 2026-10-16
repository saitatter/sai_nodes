import 'package:collection/collection.dart';
import '../definitions/node_definition.dart';
import '../diagnostics/graph_diagnostic.dart';
import '../indexing/graph_indexes.dart';
import '../geometry/node_geometry.dart';
import '../geometry/geometry.dart';
import '../model/graph_document.dart';
import '../types/graph_type_system.dart';

enum InvalidConnectionPolicy { preserve, remove }

final class _ResolvedNodeCache {
  const _ResolvedNodeCache(
    this.definition,
    this.node,
    this.space,
    this.document,
    this.connections,
    this.structures,
    this.dependencies,
    this.revision,
    this.structure,
  );
  final NodeDefinition definition;
  final GraphNode? node;
  final GraphSpace? space;
  final GraphDocument? document;
  final Map<String, GraphConnection>? connections;
  final Map<String, NodeStructure> structures;
  final Set<NodeResolutionDependency> dependencies;
  final int revision;
  final NodeStructure structure;
}

final class GraphResolution {
  GraphResolution({
    required this.document,
    required Map<String, Map<String, NodeStructure>> structures,
    required Iterable<GraphDiagnostic> diagnostics,
    required this.passes,
    required this.converged,
  }) : structures = Map.unmodifiable(
         structures.map(
           (id, values) =>
               MapEntry(id, Map<String, NodeStructure>.unmodifiable(values)),
         ),
       ),
       diagnostics = List.unmodifiable(diagnostics);
  final GraphDocument document;
  final Map<String, Map<String, NodeStructure>> structures;
  final List<GraphDiagnostic> diagnostics;
  final int passes;
  final bool converged;
  bool get hasErrors => diagnostics.any(
    (issue) => issue.severity == GraphDiagnosticSeverity.error,
  );
}

final class GraphResolver {
  GraphResolver({
    required this.definitions,
    required this.types,
    this.maxPasses = 16,
    this.invalidConnectionPolicy = InvalidConnectionPolicy.preserve,
  }) {
    if (maxPasses < 2) throw ArgumentError.value(maxPasses, 'maxPasses');
  }
  final NodeDefinitionRegistry definitions;
  final GraphTypeSystem types;
  final int maxPasses;
  final InvalidConnectionPolicy invalidConnectionPolicy;
  final Map<(String, String), _ResolvedNodeCache> _cache = {};
  Map<String, Map<String, NodeStructure>> _lastStructures = {};
  String? _lastDocumentId;

  GraphResolution resolve(GraphDocument document) {
    var current = document;
    var structures = _lastDocumentId == document.id
        ? _lastStructures
        : <String, Map<String, NodeStructure>>{};
    var passes = 0;
    var converged = false;
    final registryRevision = definitions.revision;
    final failures = <String, GraphDiagnostic>{};
    while (passes < maxPasses) {
      passes++;
      final next = <String, Map<String, NodeStructure>>{};
      final sameDocuments = Map<GraphDocument, bool>.identity();
      for (final space in current.spaces.values) {
        final resolved = <String, NodeStructure>{};
        GraphIndexes? indexes;
        final incoming = structures[space.id] ?? <String, NodeStructure>{};
        final sameSpaces = Map<GraphSpace, bool>.identity();
        final sameTopologies =
            Map<Map<String, GraphConnection>, bool>.identity();
        final sameStructures = Map<Map<String, NodeStructure>, bool>.identity();
        for (final node in space.nodes.values) {
          final definition = definitions[node.type];
          if (definition == null) {
            failures['${space.id}/${node.id}'] = GraphDiagnostic(
              code: 'missing-definition',
              message: 'Node definition ${node.type} is unavailable.',
              kind: GraphEntityKind.node,
              entityId: node.id,
              spaceId: space.id,
            );
            continue;
          }
          try {
            final cached = _cache[(space.id, node.id)];
            final reusable =
                cached != null &&
                identical(cached.definition, definition) &&
                cached.dependencies.every(
                  (dependency) => switch (dependency) {
                    NodeResolutionDependency.node => cached.node == node,
                    NodeResolutionDependency.document =>
                      sameDocuments.putIfAbsent(
                        cached.document!,
                        () => cached.document == current,
                      ),
                    NodeResolutionDependency.space => sameSpaces.putIfAbsent(
                      cached.space!,
                      () => cached.space == space,
                    ),
                    NodeResolutionDependency.topology =>
                      sameTopologies.putIfAbsent(
                        cached.connections!,
                        () => const DeepCollectionEquality().equals(
                          cached.connections,
                          space.connections,
                        ),
                      ),
                    NodeResolutionDependency.structures =>
                      sameStructures.putIfAbsent(
                        cached.structures,
                        () => const DeepCollectionEquality().equals(
                          cached.structures,
                          incoming,
                        ),
                      ),
                    NodeResolutionDependency.definitions =>
                      cached.revision == registryRevision,
                  },
                );
            if (reusable) {
              resolved[node.id] = cached.structure;
            } else {
              final context = NodeResolutionContext(
                document: current,
                space: space,
                node: node,
                indexes: () => indexes ??= GraphIndexes.fromSpace(space),
                definitions: definitions,
                structures: incoming,
              );
              final structure = definition.resolve(context);
              resolved[node.id] = structure;
              final dependencies = context.dependencies;
              _cache[(space.id, node.id)] = _ResolvedNodeCache(
                definition,
                dependencies.contains(NodeResolutionDependency.node)
                    ? node
                    : null,
                dependencies.contains(NodeResolutionDependency.space)
                    ? space
                    : null,
                dependencies.contains(NodeResolutionDependency.document)
                    ? current
                    : null,
                dependencies.contains(NodeResolutionDependency.topology)
                    ? space.connections
                    : null,
                dependencies.contains(NodeResolutionDependency.structures)
                    ? incoming
                    : const {},
                dependencies,
                registryRevision,
                structure,
              );
            }
            failures.remove('${space.id}/${node.id}');
          } catch (error) {
            failures['${space.id}/${node.id}'] = GraphDiagnostic(
              code: 'resolution-error',
              message: '$error',
              kind: GraphEntityKind.node,
              entityId: node.id,
              spaceId: space.id,
            );
          }
        }
        next[space.id] = resolved;
      }
      final same = const DeepCollectionEquality().equals(structures, next);
      structures = next;
      final beforeFrames = current;
      current = _resolveFrames(current, structures);
      final framesChanged = current != beforeFrames;
      if (definitions.revision != registryRevision) {
        throw StateError('Definitions must not mutate during resolution.');
      }
      var removed = false;
      if (invalidConnectionPolicy == InvalidConnectionPolicy.remove) {
        final invalid = _connections(current, structures);
        final spaces = {...current.spaces};
        for (final space in current.spaces.values) {
          final ids = invalid
              .where((issue) => issue.spaceId == space.id)
              .map((issue) => issue.entityId)
              .toSet();
          if (ids.isEmpty) continue;
          spaces[space.id] = space.copyWith(
            connections: {...space.connections}
              ..removeWhere((key, _) => ids.contains(key)),
            connectionPresentations: {...space.connectionPresentations}
              ..removeWhere((key, _) => ids.contains(key)),
          );
          removed = true;
        }
        if (removed) current = current.copyWith(spaces: spaces);
      }
      if (same && !removed && !framesChanged) {
        converged = true;
        break;
      }
    }
    final issues = <GraphDiagnostic>[
      ...const GraphDocumentValidator().validate(current),
      ...failures.values,
      ..._connections(current, structures),
      if (!converged)
        GraphDiagnostic(
          code: 'non-converging-definition',
          message: 'Resolution did not converge after $maxPasses passes.',
          kind: GraphEntityKind.document,
          entityId: current.id,
        ),
    ];
    _cache.removeWhere(
      (ref, _) =>
          !current.spaces.containsKey(ref.$1) ||
          !current.spaces[ref.$1]!.nodes.containsKey(ref.$2),
    );
    _lastStructures = structures;
    _lastDocumentId = current.id;
    return GraphResolution(
      document: current,
      structures: structures,
      diagnostics: issues,
      passes: passes,
      converged: converged,
    );
  }

  GraphDocument _resolveFrames(
    GraphDocument document,
    Map<String, Map<String, NodeStructure>> structures,
  ) {
    final spaces = {...document.spaces};
    var changed = false;
    for (final space in document.spaces.values) {
      if (space.frames.isEmpty) continue;
      final bounds = {
        for (final node in space.nodes.values)
          node.id: const NodeGeometryEngine()
              .compute(
                space.nodePresentations[node.id] ??
                    NodePresentation(
                      nodeId: node.id,
                      position: GraphPoint.zero,
                    ),
                structures[space.id]?[node.id],
              )
              .bounds,
      };
      final frames = {...space.frames};
      for (final frame in space.frames.values) {
        var members = frame.memberNodeIds;
        if (frame.metadata['membership'] == 'contains') {
          members = {
            for (final entry in bounds.entries)
              if (frame.bounds.contains(
                    GraphPoint(entry.value.left, entry.value.top),
                  ) &&
                  frame.bounds.contains(
                    GraphPoint(entry.value.right, entry.value.bottom),
                  ))
                entry.key,
          };
        }
        var nextBounds = frame.bounds;
        final memberBounds = members
            .map((id) => bounds[id])
            .whereType<GraphRect>();
        if (frame.autoFit && memberBounds.isNotEmpty) {
          final configured = frame.metadata['padding'];
          final padding =
              configured is num && configured.isFinite && configured >= 0
              ? configured.toDouble()
              : 24.0;
          nextBounds = memberBounds
              .reduce((a, b) => a.union(b))
              .inflate(padding);
        }
        final next = frame.copyWith(memberNodeIds: members, bounds: nextBounds);
        if (next != frame) {
          frames[frame.id] = next;
          changed = true;
        }
      }
      spaces[space.id] = space.copyWith(frames: frames);
    }
    return changed ? document.copyWith(spaces: spaces) : document;
  }

  List<GraphDiagnostic> _connections(
    GraphDocument document,
    Map<String, Map<String, NodeStructure>> structures,
  ) {
    final issues = <GraphDiagnostic>[];
    for (final space in document.spaces.values) {
      final indexes = GraphIndexes.fromSpace(space);
      for (final edge in space.connections.values) {
        void issue(String code, String message, [String? port]) => issues.add(
          GraphDiagnostic(
            code: code,
            message: message,
            kind: GraphEntityKind.connection,
            entityId: edge.id,
            spaceId: space.id,
            portId: port,
          ),
        );
        final source = structures[space.id]?[edge.from.nodeId]?.port(
          edge.from.portId,
        );
        final target = structures[space.id]?[edge.to.nodeId]?.port(
          edge.to.portId,
        );
        if (source == null) {
          issue(
            'missing-source-port',
            'Source port ${edge.from.portId} is unresolved.',
            edge.from.portId,
          );
        }
        if (target == null) {
          issue(
            'missing-target-port',
            'Target port ${edge.to.portId} is unresolved.',
            edge.to.portId,
          );
        }
        if (source == null || target == null) continue;
        if (source.direction != GraphPortDirection.output ||
            target.direction != GraphPortDirection.input) {
          issue(
            'wrong-port-direction',
            'Connections must go from output to input.',
          );
        }
        if (source.kind != target.kind ||
            (edge.kind == GraphConnectionKind.control &&
                source.kind != GraphPortKind.control) ||
            (edge.kind == GraphConnectionKind.data &&
                source.kind != GraphPortKind.data)) {
          issue(
            'port-kind-mismatch',
            'Connection and port kinds are incompatible.',
          );
        }
        if (source.kind == GraphPortKind.data &&
            !types.canConnect(
              outputType: source.dataType,
              inputType: target.dataType,
            )) {
          issue(
            'type-mismatch',
            '${source.dataType} cannot connect to ${target.dataType}.',
          );
        }
        for (final pair in [(edge.from, source), (edge.to, target)]) {
          if (pair.$2.maxConnections != null &&
              (indexes.connectionIdsByPort[pair.$1]?.length ?? 0) >
                  pair.$2.maxConnections!) {
            issue(
              'max-connections',
              'Port ${pair.$1.portId} exceeds its capacity.',
              pair.$1.portId,
            );
          }
        }
        if (edge.from.nodeId == edge.to.nodeId &&
            structures[space.id]?[edge.from.nodeId]
                    ?.constraints['allowSelfConnections'] ==
                false) {
          issue(
            'self-connection',
            'This node does not allow self-connections.',
          );
        }
      }
    }
    return issues;
  }
}
