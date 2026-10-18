import 'dart:math' as math;
import 'package:sai_nodes/sai_nodes.dart';
import 'catalog.dart';

/// A deliberately small host runtime. The graph library does not execute nodes.
class DemoRun {
  const DemoRun(this.value, this.outputs, this.visited, this.connections);
  final Object value;
  final Map<String, Object> outputs;
  final List<String> visited;
  final Set<String> connections;
}

class DemoRuntime {
  DemoRuntime(this.demo, GraphDocument document)
    : space =
          document.spaces[gallerySpace] ??
          (throw StateError('The main graph space is missing.'));
  final GraphDemo demo;
  final GraphSpace space;
  final _outputs = <String, Object>{};
  final _visiting = <String>{};
  final _order = <String>[];
  final _connections = <String>{};

  DemoRun run() {
    if (space.nodes.length > 100 || space.connections.length > 200) {
      throw StateError(
        'This playground supports up to 100 nodes and 200 connections.',
      );
    }
    final result = demo.id == 'mindmap'
        ? _idea(demo.output, {})
        : _evaluate(demo.output);
    return DemoRun(
      result,
      Map.unmodifiable(_outputs),
      List.unmodifiable(_order),
      Set.unmodifiable(_connections),
    );
  }

  Object _input(GraphNode node, String key) {
    final edges = space.connections.values
        .where((edge) => edge.to == PortRef(nodeId: node.id, portId: 'in:$key'))
        .toList();
    if (edges.length != 1) {
      throw StateError(
        'Connect exactly one source to ${demo.specFor(node).title} → $key.',
      );
    }
    _connections.add(edges.single.id);
    return _evaluate(edges.single.from.nodeId);
  }

  double _number(Object? value, String label) {
    if (value is! num || !value.isFinite) {
      throw StateError('$label must be a finite number.');
    }
    return value.toDouble();
  }

  List<double> _vector(Object? value, String label) {
    if (value is! List || value.isEmpty || value.length > 32) {
      throw StateError('$label must contain 1–32 numbers.');
    }
    return value.map((entry) => _number(entry, label)).toList();
  }

  List<Map<String, Object?>> _rows(Object? value) {
    if (value is! List || value.length > 100) {
      throw StateError('The dataset must be an array of at most 100 rows.');
    }
    return value.map((entry) {
      if (entry is! Map || entry['name'] is! String) {
        throw StateError('Each row needs a name and numeric score.');
      }
      return <String, Object?>{
        'name': entry['name'],
        'score': _number(entry['score'], 'Score'),
      };
    }).toList();
  }

  Object _evaluate(String id) {
    if (_outputs.containsKey(id)) return _outputs[id]!;
    final node = space.nodes[id];
    if (node == null) {
      throw StateError(
        'Output or connected node "$id" is missing. Undo the deletion or reset the example.',
      );
    }
    if (!_visiting.add(id)) {
      throw StateError(
        'This example needs an acyclic graph. Remove the cycle and run again.',
      );
    }
    final spec = demo.specFor(node);
    for (final field in spec.fields) {
      final value = node.data[field.id];
      if (field.value is num) {
        final number = _number(value, field.label);
        if (number < field.min || number > field.max) {
          throw StateError(
            '${field.label} must be between ${field.min} and ${field.max}.',
          );
        }
      } else if (field.value is bool && value is! bool) {
        throw StateError('${field.label} must be true or false.');
      } else if (field.choices.isNotEmpty && !field.choices.contains(value)) {
        throw StateError('Choose a supported ${field.label.toLowerCase()}.');
      }
    }
    Object input(String key) => _input(node, key);
    double number(String key) => _number(node.data[key], key);
    final data = node.data;
    final Object result;
    switch (spec.op) {
      case 'boolean':
        result = data['value']!;
      case 'number':
        result = number('value');
      case 'and':
        final pressed = input('pressed'), grounded = input('grounded');
        if (pressed is! bool || grounded is! bool) {
          throw StateError('Can jump requires boolean inputs.');
        }
        result = pressed && grounded;
      case 'impulse':
        final enabled = input('enabled');
        if (enabled is! bool) {
          throw StateError('Jump impulse requires a boolean gate.');
        }
        result = enabled ? number('strength') : 0.0;
      case 'player':
        final velocity = _number(input('velocity'), 'Velocity');
        result = {
          'jumped': velocity > 0,
          'velocity': velocity,
          'height': velocity * velocity / 19.62,
        };
      case 'less':
        result =
            _number(input('amount'), 'Amount') <
            _number(input('limit'), 'Limit');
      case 'approval':
        final approved = input('approved');
        if (approved is! bool) {
          throw StateError('Route request requires a boolean decision.');
        }
        result = {
          'approved': approved,
          'route': approved
              ? 'Automatically approved'
              : 'Manager review required',
          'next': approved ? 'Send to accounting' : 'Notify the approver',
        };
      case 'uv':
        result = '(gl_FragCoord.xy / u_resolution.xy)';
      case 'wave':
        result =
            '(0.5 + 0.5 * sin((${input('uv')}).x * ${number('frequency').toStringAsFixed(3)} + (${input('uv')}).y * 4.0 + u_time * ${number('speed').toStringAsFixed(3)}))';
      case 'palette':
        result =
            'mix(hsv(vec3(${(number('hueA') / 360).toStringAsFixed(5)}, 0.7, 0.95)), hsv(vec3(${(number('hueB') / 360).toStringAsFixed(5)}, 0.65, 0.95)), ${input('factor')})';
      case 'surface':
        result = {
          'glsl':
              'precision mediump float;\nuniform vec2 u_resolution;\nuniform float u_time;\nvec3 hsv(vec3 c) { vec3 p = abs(fract(c.xxx + vec3(0., 2./3., 1./3.)) * 6. - 3.); return c.z * mix(vec3(1.), clamp(p - 1., 0., 1.), c.y); }\nvoid main() { gl_FragColor = vec4(${input('color')}, 1.0); }',
          'renderer': 'WebGL fragment shader',
        };
      case 'rows':
        result = _rows(data['rows']);
      case 'filter':
        result = _rows(
          input('rows'),
        ).where((row) => (row['score']! as num) >= number('minimum')).toList();
      case 'normalize':
        result = [
          for (final row in _rows(input('rows')))
            {...row, 'normalized': (row['score']! as num) / 100},
        ];
      case 'report':
        final value = input('rows');
        if (value is! List) throw StateError('Report expects rows.');
        result = {
          'rows': value,
          'count': value.length,
          'average': value.isEmpty
              ? 0.0
              : value.fold<double>(
                      0,
                      (sum, row) =>
                          sum + _number((row as Map)['score'], 'Score'),
                    ) /
                    value.length,
        };
      case 'vector':
        result = _vector(data['values'], 'Feature vector');
      case 'dense':
        final vector = _vector(input('vector'), 'Layer input');
        final weights = data['weights'];
        final bias = _vector(data['bias'], 'Bias');
        if (weights is! List ||
            weights.isEmpty ||
            weights.length > 32 ||
            bias.length != weights.length) {
          throw StateError(
            'Dense weights need one row per bias, with 1–32 units.',
          );
        }
        result = [
          for (var i = 0; i < weights.length; i++)
            _dot(_vector(weights[i], 'Weight row'), vector) + bias[i],
        ];
      case 'relu':
        result = _vector(
          input('vector'),
          'ReLU input',
        ).map((value) => math.max(0.0, value)).toList();
      case 'sigmoid':
        final vector = _vector(input('vector'), 'Classifier input');
        if (vector.length != 1) {
          throw StateError('The classifier expects exactly one logit.');
        }
        final probability = 1 / (1 + math.exp(-vector.single));
        result = {
          'probability': probability,
          'class': probability >= 0.5 ? 'Class A' : 'Class B',
          'logit': vector.single,
        };
      case 'oscillator':
        result = {
          'frequency': number('frequency'),
          'waveform': data['waveform'],
        };
      case 'gain':
        result = {..._signal(input('signal')), 'gain': number('gain')};
      case 'lowpass':
        result = {..._signal(input('signal')), 'cutoff': number('cutoff')};
      case 'speaker':
        final signal = _signal(input('signal'));
        if (!signal.keys.toSet().containsAll([
          'frequency',
          'waveform',
          'gain',
          'cutoff',
        ])) {
          throw StateError(
            'Complete the oscillator, gain and filter chain first.',
          );
        }
        result = signal;
      default:
        throw StateError('Unsupported demo operation: ${spec.op}');
    }
    _visiting.remove(id);
    _order.add(id);
    _outputs[id] = result;
    return result;
  }

  Map<String, Object?> _signal(Object value) {
    if (value is! Map<String, Object?>) {
      throw StateError('Expected an audio signal.');
    }
    return value;
  }

  double _dot(List<double> weights, List<double> vector) {
    if (weights.length != vector.length) {
      throw StateError('Weight columns must match the input vector length.');
    }
    final value = weights.indexed.fold<double>(
      0,
      (sum, entry) => sum + entry.$2 * vector[entry.$1],
    );
    if (!value.isFinite) {
      throw StateError('The layer result overflowed. Use smaller weights.');
    }
    return value;
  }

  Object _idea(String id, Set<String> path) {
    if (path.contains(id)) {
      throw StateError('The idea map contains a cycle. Reconnect that branch.');
    }
    if (_outputs.containsKey(id)) return _outputs[id]!;
    final node = space.nodes[id];
    if (node == null) {
      throw StateError('The root idea is missing. Undo or reset the example.');
    }
    demo.specFor(node);
    final label = node.data['label'];
    if (label is! String || label.trim().isEmpty) {
      throw StateError('Each idea needs a label.');
    }
    final children = <Object>[];
    for (final edge in space.connections.values.where(
      (edge) => edge.from.nodeId == id,
    )) {
      _connections.add(edge.id);
      children.add(_idea(edge.to.nodeId, {...path, id}));
    }
    final value = {'label': label, 'children': children};
    _order.add(id);
    _outputs[id] = value;
    return value;
  }
}
