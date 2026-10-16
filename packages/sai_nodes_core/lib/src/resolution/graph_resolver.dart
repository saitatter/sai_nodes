import 'package:collection/collection.dart';
import '../definitions/node_definition.dart';
import '../diagnostics/graph_diagnostic.dart';
import '../indexing/graph_indexes.dart';
import '../model/graph_document.dart';
import '../types/graph_type_system.dart';

enum InvalidConnectionPolicy { preserve, remove }

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

  GraphResolution resolve(GraphDocument document) {
    var current = document;
    var structures = <String, Map<String, NodeStructure>>{};
    var passes = 0;
    var converged = false;
    final registryRevision = definitions.revision;
    final failures = <String, GraphDiagnostic>{};
    while (passes < maxPasses) {
      passes++;
      final next = <String, Map<String, NodeStructure>>{};
      for (final space in current.spaces.values) {
        final resolved = <String, NodeStructure>{};
        final indexes = GraphIndexes.fromSpace(space);
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
            resolved[node.id] = definition.resolve(
              NodeResolutionContext(
                document: current,
                space: space,
                node: node,
                indexes: indexes,
                definitions: definitions,
                structures: structures[space.id] ?? {},
              ),
            );
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
      if (same && !removed) {
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
    return GraphResolution(
      document: current,
      structures: structures,
      diagnostics: issues,
      passes: passes,
      converged: converged,
    );
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
