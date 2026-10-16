import '../model/graph_document.dart';

enum GraphDiagnosticSeverity { info, warning, error }

enum GraphEntityKind {
  document,
  space,
  node,
  connection,
  nodePresentation,
  connectionPresentation,
  frame,
  comment,
}

/// A diagnostic identifies an entity without attaching mutable state to it.
final class GraphDiagnostic {
  const GraphDiagnostic({
    required this.code,
    required this.message,
    this.severity = GraphDiagnosticSeverity.error,
    required this.kind,
    required this.entityId,
    this.spaceId,
    this.portId,
  });
  final String code;
  final String message;
  final GraphDiagnosticSeverity severity;
  final GraphEntityKind kind;
  final String entityId;
  final String? spaceId;
  final String? portId;
}

/// Structural checks only. Definition/port/type checks belong to resolution.
/// Invalid references remain in the document for a host to display and repair.
final class GraphDocumentValidator {
  const GraphDocumentValidator();
  List<GraphDiagnostic> validate(GraphDocument document) {
    final issues = <GraphDiagnostic>[];
    final seen = <GraphEntityKind, Set<String>>{};
    void report(
      String code,
      String message,
      GraphEntityKind kind,
      String id, [
      String? space,
    ]) {
      issues.add(
        GraphDiagnostic(
          code: code,
          message: message,
          kind: kind,
          entityId: id,
          spaceId: space,
        ),
      );
    }

    void identity(String key, String id, GraphEntityKind kind, String? space) {
      if (id.isEmpty) {
        report('empty-id', 'Entity ID must not be empty.', kind, key, space);
      }
      if (key != id) {
        report(
          'identity-mismatch',
          'Map key $key does not match ID $id.',
          kind,
          key,
          space,
        );
      }
      if (!(seen[kind] ??= {}).add(id)) {
        report(
          'duplicate-id',
          'ID $id occurs more than once.',
          kind,
          key,
          space,
        );
      }
    }

    if (document.id.isEmpty) {
      report(
        'empty-id',
        'Document ID must not be empty.',
        GraphEntityKind.document,
        document.id,
      );
    }
    for (final entry in document.spaces.entries) {
      final space = entry.value;
      final sid = entry.key;
      identity(sid, space.id, GraphEntityKind.space, sid);
      for (final entry in space.nodes.entries) {
        identity(entry.key, entry.value.id, GraphEntityKind.node, sid);
        if (entry.value.type.isEmpty) {
          report(
            'empty-node-type',
            'Node type must not be empty.',
            GraphEntityKind.node,
            entry.key,
            sid,
          );
        }
      }
      for (final entry in space.connections.entries) {
        final connection = entry.value;
        identity(entry.key, connection.id, GraphEntityKind.connection, sid);
        for (final endpoint in [connection.from, connection.to]) {
          if (!space.nodes.containsKey(endpoint.nodeId)) {
            report(
              'missing-node',
              'Connection references missing node ${endpoint.nodeId}.',
              GraphEntityKind.connection,
              entry.key,
              sid,
            );
          }
          if (endpoint.portId.isEmpty) {
            report(
              'empty-port-id',
              'Connection endpoint port ID must not be empty.',
              GraphEntityKind.connection,
              entry.key,
              sid,
            );
          }
        }
      }
      for (final entry in space.nodePresentations.entries) {
        final view = entry.value;
        if (entry.key != view.nodeId || !space.nodes.containsKey(view.nodeId)) {
          report(
            'invalid-presentation-reference',
            'Node presentation must reference its keyed node.',
            GraphEntityKind.nodePresentation,
            entry.key,
            sid,
          );
        }
        if (!view.position.isFinite ||
            (view.size != null && !view.size!.isValid)) {
          report(
            'invalid-geometry',
            'Node position/size is invalid.',
            GraphEntityKind.nodePresentation,
            entry.key,
            sid,
          );
        }
      }
      for (final entry in space.connectionPresentations.entries) {
        final view = entry.value;
        if (entry.key != view.connectionId ||
            !space.connections.containsKey(view.connectionId)) {
          report(
            'invalid-presentation-reference',
            'Connection presentation must reference its keyed connection.',
            GraphEntityKind.connectionPresentation,
            entry.key,
            sid,
          );
        }
        if (view.waypoints.any((point) => !point.isFinite) ||
            (view.labelOffset != null && !view.labelOffset!.isFinite)) {
          report(
            'invalid-waypoint',
            'Connection waypoint/label position must be finite.',
            GraphEntityKind.connectionPresentation,
            entry.key,
            sid,
          );
        }
      }
      for (final entry in space.frames.entries) {
        final frame = entry.value;
        identity(entry.key, frame.id, GraphEntityKind.frame, sid);
        if (!frame.bounds.isValid) {
          report(
            'invalid-geometry',
            'Frame bounds are invalid.',
            GraphEntityKind.frame,
            entry.key,
            sid,
          );
        }
        for (final member in frame.memberNodeIds) {
          if (!space.nodes.containsKey(member)) {
            report(
              'invalid-frame-member',
              'Frame references missing node $member.',
              GraphEntityKind.frame,
              entry.key,
              sid,
            );
          }
        }
      }
      for (final entry in space.comments.entries) {
        identity(entry.key, entry.value.id, GraphEntityKind.comment, sid);
        if (!entry.value.bounds.isValid) {
          report(
            'invalid-geometry',
            'Comment bounds are invalid.',
            GraphEntityKind.comment,
            entry.key,
            sid,
          );
        }
      }
    }
    return List.unmodifiable(issues);
  }
}
