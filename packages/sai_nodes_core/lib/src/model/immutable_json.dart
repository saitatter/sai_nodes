import 'dart:collection';

typedef GraphJson = Map<String, Object?>;

/// Takes ownership of nested JSON values without retaining mutable host aliases.
GraphJson freezeJson(GraphJson value) =>
    _freeze(value, HashSet.identity()) as GraphJson;

Object? _freeze(Object? value, Set<Object> ancestors) {
  if (value == null || value is String || value is bool) return value;
  if (value is num) {
    if (!value.isFinite) {
      throw ArgumentError('Graph JSON numbers must be finite.');
    }
    return value;
  }
  if (!ancestors.add(value)) {
    throw ArgumentError('Graph JSON cannot contain cycles.');
  }
  try {
    if (value is Map) {
      final copy = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw ArgumentError('Graph JSON keys must be strings.');
        }
        copy[entry.key as String] = _freeze(entry.value, ancestors);
      }
      return Map<String, Object?>.unmodifiable(copy);
    }
    if (value is List) {
      return List<Object?>.unmodifiable(
        value.map((item) => _freeze(item, ancestors)),
      );
    }
    throw ArgumentError('Graph data must contain JSON values.');
  } finally {
    ancestors.remove(value);
  }
}
