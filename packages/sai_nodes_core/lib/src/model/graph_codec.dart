part of 'graph_document.dart';

GraphJson _encodeDocument(GraphDocument document) => {
  'schemaVersion': 1,
  'id': document.id,
  'spaces': document.spaces.map(
    (key, space) => MapEntry(key, {
      'id': space.id,
      'nodes': space.nodes.map(
        (key, node) => MapEntry(key, {
          'id': node.id,
          'type': node.type,
          'data': node.data,
          'metadata': node.metadata,
        }),
      ),
      'connections': space.connections.map(
        (key, connection) => MapEntry(key, {
          'id': connection.id,
          'from': {
            'nodeId': connection.from.nodeId,
            'portId': connection.from.portId,
          },
          'to': {
            'nodeId': connection.to.nodeId,
            'portId': connection.to.portId,
          },
          'kind': connection.kind.name,
          'data': connection.data,
        }),
      ),
      'nodePresentations': space.nodePresentations.map(
        (key, view) => MapEntry(key, {
          'nodeId': view.nodeId,
          'position': _pointJson(view.position),
          'size': view.size == null
              ? null
              : {'width': view.size!.width, 'height': view.size!.height},
          'title': view.title,
          'collapsed': view.collapsed,
          'metadata': view.metadata,
        }),
      ),
      'connectionPresentations': space.connectionPresentations.map(
        (key, view) => MapEntry(key, {
          'connectionId': view.connectionId,
          'waypoints': view.waypoints.map(_pointJson).toList(),
          'label': view.label,
          'labelOffset': view.labelOffset == null
              ? null
              : _pointJson(view.labelOffset!),
          'metadata': view.metadata,
        }),
      ),
      'frames': space.frames.map(
        (key, frame) => MapEntry(key, {
          'id': frame.id,
          'bounds': _rectJson(frame.bounds),
          'title': frame.title,
          'memberNodeIds': frame.memberNodeIds.toList()..sort(),
          'autoFit': frame.autoFit,
          'metadata': frame.metadata,
        }),
      ),
      'comments': space.comments.map(
        (key, comment) => MapEntry(key, {
          'id': comment.id,
          'bounds': _rectJson(comment.bounds),
          'text': comment.text,
          'metadata': comment.metadata,
        }),
      ),
      'metadata': space.metadata,
    }),
  ),
  'metadata': document.metadata,
};

GraphJson _pointJson(GraphPoint point) => {'x': point.x, 'y': point.y};
GraphJson _rectJson(GraphRect rect) => {
  'left': rect.left,
  'top': rect.top,
  'width': rect.width,
  'height': rect.height,
};

GraphJson _object(Object? value, String path) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('$path must be an object with string keys.');
  }
  return Map<String, Object?>.from(value);
}

final class _Reader {
  _Reader(Object? value, this.path, Set<String> fields)
    : json = _object(value, path) {
    final unknown = json.keys.where((key) => !fields.contains(key));
    if (unknown.isNotEmpty) {
      throw FormatException(
        '$path has unsupported fields: ${unknown.join(', ')}',
      );
    }
  }
  final GraphJson json;
  final String path;
  String string(String key) {
    final value = json[key];
    if (value is! String) throw FormatException('$path.$key must be a string.');
    return value;
  }

  String? nullableString(String key) => json[key] == null ? null : string(key);
  double number(String key) {
    final value = json[key];
    if (value is! num || !value.isFinite) {
      throw FormatException('$path.$key must be a finite number.');
    }
    return value.toDouble();
  }

  bool boolean(String key) {
    final value = json.containsKey(key) ? json[key] : false;
    if (value is! bool) throw FormatException('$path.$key must be a boolean.');
    return value;
  }

  GraphJson object(String key) => _object(
    json.containsKey(key) ? json[key] : <String, Object?>{},
    '$path.$key',
  );
  List<Object?> list(String key) {
    final value = json.containsKey(key) ? json[key] : <Object?>[];
    if (value is! List) throw FormatException('$path.$key must be an array.');
    return List<Object?>.from(value);
  }

  Map<String, T> entities<T>(
    String key,
    T Function(_Reader) decode,
    Set<String> fields,
  ) => object(key).map(
    (id, value) =>
        MapEntry(id, decode(_Reader(value, '$path.$key.$id', fields))),
  );
}

GraphPoint _point(Object? value, String path) {
  final reader = _Reader(value, path, {'x', 'y'});
  return GraphPoint(reader.number('x'), reader.number('y'));
}

GraphRect _rect(Object? value, String path) {
  final reader = _Reader(value, path, {'left', 'top', 'width', 'height'});
  return GraphRect(
    reader.number('left'),
    reader.number('top'),
    reader.number('width'),
    reader.number('height'),
  );
}

PortRef _port(Object? value, String path) {
  final reader = _Reader(value, path, {'nodeId', 'portId'});
  return PortRef(
    nodeId: reader.string('nodeId'),
    portId: reader.string('portId'),
  );
}

GraphDocument _decodeDocument(GraphJson json) {
  final reader = _Reader(json, 'graph', {
    'schemaVersion',
    'id',
    'spaces',
    'metadata',
  });
  if (json['schemaVersion'] is! int || json['schemaVersion'] != 1) {
    throw const FormatException('Unsupported graph schemaVersion; expected 1.');
  }
  return GraphDocument(
    id: reader.string('id'),
    metadata: reader.object('metadata'),
    spaces: reader.entities(
      'spaces',
      (space) => GraphSpace(
        id: space.string('id'),
        metadata: space.object('metadata'),
        nodes: space.entities(
          'nodes',
          (node) => GraphNode(
            id: node.string('id'),
            type: node.string('type'),
            data: node.object('data'),
            metadata: node.object('metadata'),
          ),
          {'id', 'type', 'data', 'metadata'},
        ),
        connections: space.entities('connections', (connection) {
          final kind = connection.string('kind');
          final parsed = GraphConnectionKind.values
              .where((value) => value.name == kind)
              .firstOrNull;
          if (parsed == null) {
            throw FormatException(
              '${connection.path}.kind is unsupported: $kind',
            );
          }
          return GraphConnection(
            id: connection.string('id'),
            from: _port(connection.json['from'], '${connection.path}.from'),
            to: _port(connection.json['to'], '${connection.path}.to'),
            kind: parsed,
            data: connection.object('data'),
          );
        }, {'id', 'from', 'to', 'kind', 'data'}),
        nodePresentations: space.entities('nodePresentations', (view) {
          final size = view.json['size'] == null
              ? null
              : _Reader(view.json['size'], '${view.path}.size', {
                  'width',
                  'height',
                });
          return NodePresentation(
            nodeId: view.string('nodeId'),
            position: _point(view.json['position'], '${view.path}.position'),
            size: size == null
                ? null
                : GraphSize(size.number('width'), size.number('height')),
            title: view.nullableString('title'),
            collapsed: view.boolean('collapsed'),
            metadata: view.object('metadata'),
          );
        }, {'nodeId', 'position', 'size', 'title', 'collapsed', 'metadata'}),
        connectionPresentations: space.entities(
          'connectionPresentations',
          (view) => ConnectionPresentation(
            connectionId: view.string('connectionId'),
            waypoints: view
                .list('waypoints')
                .indexed
                .map(
                  (entry) =>
                      _point(entry.$2, '${view.path}.waypoints[${entry.$1}]'),
                )
                .toList(),
            label: view.nullableString('label'),
            labelOffset: view.json['labelOffset'] == null
                ? null
                : _point(view.json['labelOffset'], '${view.path}.labelOffset'),
            metadata: view.object('metadata'),
          ),
          {'connectionId', 'waypoints', 'label', 'labelOffset', 'metadata'},
        ),
        frames: space.entities('frames', (frame) {
          final members = frame.list('memberNodeIds');
          if (members.any((id) => id is! String)) {
            throw FormatException(
              '${frame.path}.memberNodeIds must contain strings.',
            );
          }
          if (members.toSet().length != members.length) {
            throw FormatException(
              '${frame.path}.memberNodeIds contains duplicate IDs.',
            );
          }
          return GraphFrame(
            id: frame.string('id'),
            bounds: _rect(frame.json['bounds'], '${frame.path}.bounds'),
            title: frame.string('title'),
            memberNodeIds: members.cast<String>().toSet(),
            autoFit: frame.boolean('autoFit'),
            metadata: frame.object('metadata'),
          );
        }, {'id', 'bounds', 'title', 'memberNodeIds', 'autoFit', 'metadata'}),
        comments: space.entities(
          'comments',
          (comment) => GraphComment(
            id: comment.string('id'),
            bounds: _rect(comment.json['bounds'], '${comment.path}.bounds'),
            text: comment.string('text'),
            metadata: comment.object('metadata'),
          ),
          {'id', 'bounds', 'text', 'metadata'},
        ),
      ),
      {
        'id',
        'nodes',
        'connections',
        'nodePresentations',
        'connectionPresentations',
        'frames',
        'comments',
        'metadata',
      },
    ),
  );
}
