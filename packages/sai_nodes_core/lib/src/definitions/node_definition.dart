import 'package:collection/collection.dart';

import '../indexing/graph_indexes.dart';
import '../model/graph_document.dart';
import '../model/immutable_json.dart';

enum GraphPortDirection { input, output }

enum GraphPortKind { control, data }

enum GraphFieldKind { string, number, boolean, choice, json, custom }

final class ResolvedPort {
  ResolvedPort({
    required this.id,
    required this.direction,
    required this.kind,
    this.dataType = 'core.any',
    required this.label,
    this.maxConnections,
    GraphJson metadata = const {},
  }) : metadata = freezeJson(metadata) {
    if (id.isEmpty || (maxConnections != null && maxConnections! < 0)) {
      throw ArgumentError(
        'Ports require a stable ID and nonnegative capacity.',
      );
    }
  }
  final String id;
  final GraphPortDirection direction;
  final GraphPortKind kind;
  final String dataType;
  final String label;
  final int? maxConnections;
  final GraphJson metadata;
  @override
  bool operator ==(Object other) =>
      other is ResolvedPort &&
      id == other.id &&
      direction == other.direction &&
      kind == other.kind &&
      dataType == other.dataType &&
      label == other.label &&
      maxConnections == other.maxConnections &&
      const DeepCollectionEquality().equals(metadata, other.metadata);
  @override
  int get hashCode => Object.hash(
    id,
    direction,
    kind,
    dataType,
    label,
    maxConnections,
    const DeepCollectionEquality().hash(metadata),
  );
}

final class ResolvedField {
  ResolvedField({
    required this.id,
    required this.label,
    required this.kind,
    List<String>? dataPath,
    this.dataType = 'core.any',
    GraphJson metadata = const {},
  }) : dataPath = List.unmodifiable(dataPath ?? [id]),
       metadata = freezeJson(metadata) {
    if (id.isEmpty || this.dataPath.isEmpty) {
      throw ArgumentError('Fields require a stable ID and data path.');
    }
  }
  final String id;
  final String label;
  final GraphFieldKind kind;
  final String dataType;
  final List<String> dataPath;
  final GraphJson metadata;
  @override
  bool operator ==(Object other) =>
      other is ResolvedField &&
      id == other.id &&
      label == other.label &&
      kind == other.kind &&
      dataType == other.dataType &&
      const DeepCollectionEquality().equals(dataPath, other.dataPath) &&
      const DeepCollectionEquality().equals(metadata, other.metadata);
  @override
  int get hashCode => Object.hash(
    id,
    label,
    kind,
    dataType,
    const DeepCollectionEquality().hash(dataPath),
    const DeepCollectionEquality().hash(metadata),
  );
}

final class NodeStructure {
  NodeStructure({
    Iterable<ResolvedPort> ports = const [],
    Iterable<ResolvedField> fields = const [],
    GraphJson constraints = const {},
  }) : ports = List.unmodifiable(ports),
       fields = List.unmodifiable(fields),
       constraints = freezeJson(constraints) {
    if (this.ports.map((port) => port.id).toSet().length != this.ports.length) {
      throw ArgumentError('Port IDs must be unique across both directions.');
    }
    if (this.fields.map((field) => field.id).toSet().length !=
        this.fields.length) {
      throw ArgumentError('Field IDs must be unique.');
    }
  }
  final List<ResolvedPort> ports;
  final List<ResolvedField> fields;
  final GraphJson constraints;
  ResolvedPort? port(String id) =>
      ports.where((port) => port.id == id).firstOrNull;
  @override
  bool operator ==(Object other) =>
      other is NodeStructure &&
      const DeepCollectionEquality().equals(ports, other.ports) &&
      const DeepCollectionEquality().equals(fields, other.fields) &&
      const DeepCollectionEquality().equals(constraints, other.constraints);
  @override
  int get hashCode => Object.hash(
    const DeepCollectionEquality().hash(ports),
    const DeepCollectionEquality().hash(fields),
    const DeepCollectionEquality().hash(constraints),
  );
}

final class NodeVisualStyle {
  const NodeVisualStyle({this.color = 0xff8b5cf6, this.icon, this.category});
  final int color;
  final String? icon;
  final String? category;
}

class NodeDefinitionContext {
  const NodeDefinitionContext({
    required this.document,
    required this.space,
    required this.node,
  });
  final GraphDocument document;
  final GraphSpace space;
  final GraphNode node;
}

final class NodeVisualContext extends NodeDefinitionContext {
  const NodeVisualContext({
    required super.document,
    required super.space,
    required super.node,
  });
}

final class NodeResolutionContext extends NodeDefinitionContext {
  NodeResolutionContext({
    required super.document,
    required super.space,
    required super.node,
    required this.indexes,
    required this.definitions,
    required Map<String, NodeStructure> structures,
  }) : structures = Map.unmodifiable(structures);
  final GraphIndexes indexes;
  final NodeDefinitionLookup definitions;

  /// Previous fixed-point pass, not mutable intermediate structures.
  final Map<String, NodeStructure> structures;
}

abstract interface class NodeDefinition {
  String get type;
  String label(NodeDefinitionContext context);
  NodeStructure resolve(NodeResolutionContext context);
  NodeVisualStyle style(NodeVisualContext context);
}

abstract interface class PortFamily {
  Iterable<ResolvedPort> resolve(NodeResolutionContext context);
}

final class StaticPortFamily implements PortFamily {
  StaticPortFamily(Iterable<ResolvedPort> ports)
    : ports = List.unmodifiable(ports);
  final List<ResolvedPort> ports;
  @override
  Iterable<ResolvedPort> resolve(NodeResolutionContext context) => ports;
}

final class DynamicPortFamily implements PortFamily {
  const DynamicPortFamily(this.resolver);
  final Iterable<ResolvedPort> Function(NodeResolutionContext) resolver;
  @override
  Iterable<ResolvedPort> resolve(NodeResolutionContext context) =>
      resolver(context);
}

abstract interface class FieldFamily {
  Iterable<ResolvedField> resolve(NodeResolutionContext context);
}

final class StaticFieldFamily implements FieldFamily {
  StaticFieldFamily(Iterable<ResolvedField> fields)
    : fields = List.unmodifiable(fields);
  final List<ResolvedField> fields;
  @override
  Iterable<ResolvedField> resolve(NodeResolutionContext context) => fields;
}

final class DynamicFieldFamily implements FieldFamily {
  const DynamicFieldFamily(this.resolver);
  final Iterable<ResolvedField> Function(NodeResolutionContext) resolver;
  @override
  Iterable<ResolvedField> resolve(NodeResolutionContext context) =>
      resolver(context);
}

final class DeclarativeNodeDefinition implements NodeDefinition {
  DeclarativeNodeDefinition({
    required this.type,
    required this.displayName,
    Iterable<PortFamily> ports = const [],
    Iterable<FieldFamily> fields = const [],
    this.visualStyle = const NodeVisualStyle(),
    GraphJson constraints = const {},
  }) : ports = List.unmodifiable(ports),
       fields = List.unmodifiable(fields),
       constraints = freezeJson(constraints);
  @override
  final String type;
  final String displayName;
  final List<PortFamily> ports;
  final List<FieldFamily> fields;
  final NodeVisualStyle visualStyle;
  final GraphJson constraints;
  @override
  String label(NodeDefinitionContext context) => displayName;
  @override
  NodeStructure resolve(NodeResolutionContext context) => NodeStructure(
    ports: ports.expand((family) => family.resolve(context)),
    fields: fields.expand((family) => family.resolve(context)),
    constraints: constraints,
  );
  @override
  NodeVisualStyle style(NodeVisualContext context) => visualStyle;
}

/// Registry changes invalidate controller resolution synchronously.
abstract interface class NodeDefinitionLookup {
  int get revision;
  Map<String, NodeDefinition> get definitions;
  NodeDefinition? operator [](String type);
}

final class NodeDefinitionRegistry implements NodeDefinitionLookup {
  final Map<String, NodeDefinition> _definitions = {};
  final Set<void Function()> _listeners = {};
  int _revision = 0;
  int get revision => _revision;
  Map<String, NodeDefinition> get definitions => Map.unmodifiable(_definitions);
  NodeDefinition? operator [](String type) => _definitions[type];
  void register(NodeDefinition definition, {bool replace = false}) {
    if (definition.type.isEmpty ||
        (!replace && _definitions.containsKey(definition.type))) {
      throw ArgumentError(
        'Invalid or duplicate definition: ${definition.type}',
      );
    }
    _definitions[definition.type] = definition;
    _changed();
  }

  void unregister(String type) {
    if (_definitions.remove(type) != null) _changed();
  }

  void invalidate() => _changed();
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void _changed() {
    _revision++;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}
