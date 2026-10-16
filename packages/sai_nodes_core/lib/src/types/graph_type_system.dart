final class GraphDataType {
  GraphDataType({
    required this.id,
    required this.label,
    Set<String> acceptedSourceTypeIds = const {},
  }) : acceptedSourceTypeIds = Set.unmodifiable(acceptedSourceTypeIds) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Type IDs must not be empty.');
    }
  }
  final String id;
  final String label;

  /// Explicit directional compatibility. It does not create conversion nodes.
  final Set<String> acceptedSourceTypeIds;
}

final class GraphTypeSystem {
  GraphTypeSystem({
    Iterable<GraphDataType> types = const [],
    Set<String>? anyAccepts,
  }) : _anyAccepts = anyAccepts == null ? null : Set.unmodifiable(anyAccepts) {
    for (final type in types) {
      register(type);
    }
  }
  factory GraphTypeSystem.core({Set<String>? anyAccepts}) => GraphTypeSystem(
    anyAccepts: anyAccepts,
    types: [
      for (final id in [
        'any',
        'string',
        'number',
        'boolean',
        'object',
        'array',
      ])
        GraphDataType(id: 'core.$id', label: id),
    ],
  );
  final Map<String, GraphDataType> _types = {};
  final Set<String>? _anyAccepts;
  Map<String, GraphDataType> get types => Map.unmodifiable(_types);
  void register(GraphDataType type) {
    if (_types.containsKey(type.id)) {
      throw ArgumentError('Duplicate graph type: ${type.id}');
    }
    _types[type.id] = type;
  }

  bool canConnect({required String outputType, required String inputType}) {
    if (outputType.isEmpty || inputType.isEmpty) return false;
    if (outputType == inputType) return true;
    if (!_types.containsKey(outputType) || !_types.containsKey(inputType)) {
      return false;
    }
    if (inputType == 'core.any') {
      return _anyAccepts?.contains(outputType) ?? true;
    }
    return _types[inputType]!.acceptedSourceTypeIds.contains(outputType);
  }
}
