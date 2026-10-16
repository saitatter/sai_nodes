import 'package:collection/collection.dart';

import '../geometry/geometry.dart';
import 'immutable_json.dart';

export 'immutable_json.dart' show GraphJson;
part 'graph_codec.dart';

const _absent = Object();
const _equality = DeepCollectionEquality();

abstract base class _GraphValue {
  const _GraphValue();
  List<Object?> get _values;
  @override
  bool operator ==(Object other) =>
      other is _GraphValue &&
      runtimeType == other.runtimeType &&
      _equality.equals(_values, other._values);
  @override
  int get hashCode => Object.hash(runtimeType, _equality.hash(_values));
}

/// The sole persisted source of truth. Runtime, camera and selection are external.
final class GraphDocument extends _GraphValue {
  GraphDocument({
    required this.id,
    required Map<String, GraphSpace> spaces,
    GraphJson metadata = const {},
  }) : spaces = Map.unmodifiable(spaces),
       metadata = freezeJson(metadata);
  final String id;
  final Map<String, GraphSpace> spaces;
  final GraphJson metadata;
  GraphDocument copyWith({
    Map<String, GraphSpace>? spaces,
    GraphJson? metadata,
  }) => GraphDocument(
    id: id,
    spaces: spaces ?? this.spaces,
    metadata: metadata ?? this.metadata,
  );
  GraphJson toJson() => _encodeDocument(this);
  factory GraphDocument.fromJson(GraphJson json) => _decodeDocument(json);
  @override
  List<Object?> get _values => [id, spaces, metadata];
}

final class GraphSpace extends _GraphValue {
  GraphSpace({
    required this.id,
    Map<String, GraphNode> nodes = const {},
    Map<String, GraphConnection> connections = const {},
    Map<String, NodePresentation> nodePresentations = const {},
    Map<String, ConnectionPresentation> connectionPresentations = const {},
    Map<String, GraphFrame> frames = const {},
    Map<String, GraphComment> comments = const {},
    GraphJson metadata = const {},
  }) : nodes = Map.unmodifiable(nodes),
       connections = Map.unmodifiable(connections),
       nodePresentations = Map.unmodifiable(nodePresentations),
       connectionPresentations = Map.unmodifiable(connectionPresentations),
       frames = Map.unmodifiable(frames),
       comments = Map.unmodifiable(comments),
       metadata = freezeJson(metadata);
  final String id;
  final Map<String, GraphNode> nodes;
  final Map<String, GraphConnection> connections;
  final Map<String, NodePresentation> nodePresentations;
  final Map<String, ConnectionPresentation> connectionPresentations;
  final Map<String, GraphFrame> frames;
  final Map<String, GraphComment> comments;
  final GraphJson metadata;
  GraphSpace copyWith({
    Map<String, GraphNode>? nodes,
    Map<String, GraphConnection>? connections,
    Map<String, NodePresentation>? nodePresentations,
    Map<String, ConnectionPresentation>? connectionPresentations,
    Map<String, GraphFrame>? frames,
    Map<String, GraphComment>? comments,
    GraphJson? metadata,
  }) => GraphSpace(
    id: id,
    nodes: nodes ?? this.nodes,
    connections: connections ?? this.connections,
    nodePresentations: nodePresentations ?? this.nodePresentations,
    connectionPresentations:
        connectionPresentations ?? this.connectionPresentations,
    frames: frames ?? this.frames,
    comments: comments ?? this.comments,
    metadata: metadata ?? this.metadata,
  );
  @override
  List<Object?> get _values => [
    id,
    nodes,
    connections,
    nodePresentations,
    connectionPresentations,
    frames,
    comments,
    metadata,
  ];
}

final class GraphNode extends _GraphValue {
  GraphNode({
    required this.id,
    required this.type,
    GraphJson data = const {},
    GraphJson metadata = const {},
  }) : data = freezeJson(data),
       metadata = freezeJson(metadata);
  final String id;
  final String type;
  final GraphJson data;
  final GraphJson metadata;
  GraphNode copyWith({String? type, GraphJson? data, GraphJson? metadata}) =>
      GraphNode(
        id: id,
        type: type ?? this.type,
        data: data ?? this.data,
        metadata: metadata ?? this.metadata,
      );
  @override
  List<Object?> get _values => [id, type, data, metadata];
}

final class NodePresentation extends _GraphValue {
  NodePresentation({
    required this.nodeId,
    required this.position,
    this.size,
    this.title,
    this.collapsed = false,
    GraphJson metadata = const {},
  }) : metadata = freezeJson(metadata);
  final String nodeId;
  final GraphPoint position;
  final GraphSize? size;
  final String? title;
  final bool collapsed;
  final GraphJson metadata;
  NodePresentation copyWith({
    GraphPoint? position,
    Object? size = _absent,
    Object? title = _absent,
    bool? collapsed,
    GraphJson? metadata,
  }) => NodePresentation(
    nodeId: nodeId,
    position: position ?? this.position,
    size: identical(size, _absent) ? this.size : size as GraphSize?,
    title: identical(title, _absent) ? this.title : title as String?,
    collapsed: collapsed ?? this.collapsed,
    metadata: metadata ?? this.metadata,
  );
  @override
  List<Object?> get _values => [
    nodeId,
    position,
    size,
    title,
    collapsed,
    metadata,
  ];
}

enum GraphConnectionKind { control, data, custom }

final class PortRef extends _GraphValue {
  const PortRef({required this.nodeId, required this.portId});
  final String nodeId;
  final String portId;
  @override
  List<Object?> get _values => [nodeId, portId];
}

final class GraphConnection extends _GraphValue {
  GraphConnection({
    required this.id,
    required this.from,
    required this.to,
    required this.kind,
    GraphJson data = const {},
  }) : data = freezeJson(data);
  final String id;
  final PortRef from;
  final PortRef to;
  final GraphConnectionKind kind;
  final GraphJson data;
  GraphConnection copyWith({
    PortRef? from,
    PortRef? to,
    GraphConnectionKind? kind,
    GraphJson? data,
  }) => GraphConnection(
    id: id,
    from: from ?? this.from,
    to: to ?? this.to,
    kind: kind ?? this.kind,
    data: data ?? this.data,
  );
  @override
  List<Object?> get _values => [id, from, to, kind, data];
}

final class ConnectionPresentation extends _GraphValue {
  ConnectionPresentation({
    required this.connectionId,
    List<GraphPoint> waypoints = const [],
    this.label,
    this.labelOffset,
    GraphJson metadata = const {},
  }) : waypoints = List.unmodifiable(waypoints),
       metadata = freezeJson(metadata);
  final String connectionId;
  final List<GraphPoint> waypoints;
  final String? label;
  final GraphPoint? labelOffset;
  final GraphJson metadata;
  ConnectionPresentation copyWith({
    List<GraphPoint>? waypoints,
    Object? label = _absent,
    Object? labelOffset = _absent,
    GraphJson? metadata,
  }) => ConnectionPresentation(
    connectionId: connectionId,
    waypoints: waypoints ?? this.waypoints,
    label: identical(label, _absent) ? this.label : label as String?,
    labelOffset: identical(labelOffset, _absent)
        ? this.labelOffset
        : labelOffset as GraphPoint?,
    metadata: metadata ?? this.metadata,
  );
  @override
  List<Object?> get _values => [
    connectionId,
    waypoints,
    label,
    labelOffset,
    metadata,
  ];
}

final class GraphFrame extends _GraphValue {
  GraphFrame({
    required this.id,
    required this.bounds,
    required this.title,
    Set<String> memberNodeIds = const {},
    this.autoFit = false,
    GraphJson metadata = const {},
  }) : memberNodeIds = Set.unmodifiable(memberNodeIds),
       metadata = freezeJson(metadata);
  final String id;
  final GraphRect bounds;
  final String title;
  final Set<String> memberNodeIds;
  final bool autoFit;
  final GraphJson metadata;
  GraphFrame copyWith({
    GraphRect? bounds,
    String? title,
    Set<String>? memberNodeIds,
    bool? autoFit,
    GraphJson? metadata,
  }) => GraphFrame(
    id: id,
    bounds: bounds ?? this.bounds,
    title: title ?? this.title,
    memberNodeIds: memberNodeIds ?? this.memberNodeIds,
    autoFit: autoFit ?? this.autoFit,
    metadata: metadata ?? this.metadata,
  );
  @override
  List<Object?> get _values => [
    id,
    bounds,
    title,
    memberNodeIds,
    autoFit,
    metadata,
  ];
}

final class GraphComment extends _GraphValue {
  GraphComment({
    required this.id,
    required this.bounds,
    required this.text,
    GraphJson metadata = const {},
  }) : metadata = freezeJson(metadata);
  final String id;
  final GraphRect bounds;
  final String text;
  final GraphJson metadata;
  GraphComment copyWith({
    GraphRect? bounds,
    String? text,
    GraphJson? metadata,
  }) => GraphComment(
    id: id,
    bounds: bounds ?? this.bounds,
    text: text ?? this.text,
    metadata: metadata ?? this.metadata,
  );
  @override
  List<Object?> get _values => [id, bounds, text, metadata];
}
