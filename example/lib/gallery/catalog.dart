import 'package:flutter/material.dart';
import 'package:sai_nodes/sai_nodes.dart';

const gallerySpace = 'main';

class DemoField {
  const DemoField(
    this.id,
    this.label,
    this.value, {
    this.min = 0,
    this.max = 1,
    this.choices = const [],
  });
  final String id, label;
  final Object value;
  final double min, max;
  final List<String> choices;
  GraphFieldKind get kind => value is bool
      ? GraphFieldKind.boolean
      : value is num
      ? GraphFieldKind.number
      : value is List
      ? GraphFieldKind.json
      : choices.isNotEmpty
      ? GraphFieldKind.choice
      : GraphFieldKind.string;
}

class DemoNode {
  const DemoNode(
    this.id,
    this.title,
    this.op,
    this.x,
    this.y, {
    this.inputs = const {},
    this.output = 'core.number',
    this.fields = const [],
  });
  final String id, title, op, output;
  final double x, y;
  final Map<String, String> inputs;
  final List<DemoField> fields;
  String type(String demo) => 'gallery.$demo.$id';
  GraphJson get defaults => {for (final field in fields) field.id: field.value};
}

class DemoEdge {
  const DemoEdge(
    this.from,
    this.to, [
    this.input = 'value',
    this.waypoints = const [],
  ]);
  final String from, to, input;
  final List<GraphPoint> waypoints;
}

class GraphDemo {
  const GraphDemo({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.hint,
    required this.icon,
    required this.color,
    required this.nodes,
    required this.edges,
    this.output = 'output',
  });
  final String id, category, title, description, hint, output;
  final IconData icon;
  final Color color;
  final List<DemoNode> nodes;
  final List<DemoEdge> edges;

  NodeDefinitionRegistry definitions() {
    final registry = NodeDefinitionRegistry();
    for (final spec in nodes) {
      registry.register(
        DeclarativeNodeDefinition(
          type: spec.type(id),
          displayName: spec.title,
          visualStyle: NodeVisualStyle(color: color.toARGB32()),
          ports: [
            StaticPortFamily([
              for (final port in spec.inputs.entries)
                ResolvedPort(
                  id: 'in:${port.key}',
                  direction: GraphPortDirection.input,
                  kind: GraphPortKind.data,
                  dataType: port.value,
                  label: port.key,
                  maxConnections: 1,
                ),
              ResolvedPort(
                id: 'out',
                direction: GraphPortDirection.output,
                kind: GraphPortKind.data,
                dataType: spec.output,
                label: 'result',
              ),
            ]),
          ],
          fields: [
            StaticFieldFamily([
              for (final field in spec.fields)
                ResolvedField(
                  id: field.id,
                  label: field.label,
                  kind: field.kind,
                ),
            ]),
          ],
        ),
      );
    }
    return registry;
  }

  GraphDocument document() => GraphDocument(
    id: 'gallery:$id',
    spaces: {
      gallerySpace: GraphSpace(
        id: gallerySpace,
        nodes: {
          for (final spec in nodes)
            spec.id: GraphNode(
              id: spec.id,
              type: spec.type(id),
              data: spec.defaults,
            ),
        },
        nodePresentations: {
          for (final spec in nodes)
            spec.id: NodePresentation(
              nodeId: spec.id,
              position: GraphPoint(spec.x, spec.y),
            ),
        },
        connections: {
          for (final entry in edges.indexed)
            'edge:${entry.$1}': GraphConnection(
              id: 'edge:${entry.$1}',
              from: PortRef(nodeId: entry.$2.from, portId: 'out'),
              to: PortRef(nodeId: entry.$2.to, portId: 'in:${entry.$2.input}'),
              kind: GraphConnectionKind.data,
            ),
        },
        connectionPresentations: {
          for (final entry in edges.indexed)
            if (entry.$2.waypoints.isNotEmpty)
              'edge:${entry.$1}': ConnectionPresentation(
                connectionId: 'edge:${entry.$1}',
                waypoints: entry.$2.waypoints,
              ),
        },
      ),
    },
  );

  GraphController controller() {
    final types = GraphTypeSystem.core();
    for (final id in ['uv', 'scalar', 'color', 'audio']) {
      types.register(GraphDataType(id: 'demo.$id', label: id));
    }
    return GraphController(
      document: document(),
      resolver: GraphResolver(definitions: definitions(), types: types),
    );
  }

  DemoNode specFor(GraphNode node) => nodes.firstWhere(
    (spec) => spec.type(id) == node.type,
    orElse: () => throw StateError('Unknown demo node type: ${node.type}'),
  );
}

const graphDemos = <GraphDemo>[
  GraphDemo(
    id: 'game',
    category: 'Visual scripting',
    title: 'Give an idea a little jump.',
    description:
        'A tiny game mechanic. Gate an input, apply an impulse, and watch your character take off.',
    hint: 'Try turning Grounded off, or change the jump strength.',
    icon: Icons.sports_esports_outlined,
    color: Color(0xffa998ff),
    nodes: [
      DemoNode(
        'input',
        'Jump input',
        'boolean',
        0,
        0,
        output: 'core.boolean',
        fields: [DemoField('value', 'Space pressed', true)],
      ),
      DemoNode(
        'grounded',
        'Grounded?',
        'boolean',
        0,
        200,
        output: 'core.boolean',
        fields: [DemoField('value', 'On the ground', true)],
      ),
      DemoNode(
        'gate',
        'Can jump',
        'and',
        340,
        80,
        inputs: {'pressed': 'core.boolean', 'grounded': 'core.boolean'},
        output: 'core.boolean',
      ),
      DemoNode(
        'impulse',
        'Jump impulse',
        'impulse',
        680,
        80,
        inputs: {'enabled': 'core.boolean'},
        fields: [DemoField('strength', 'Jump strength', 7.0, min: 1, max: 12)],
      ),
      DemoNode(
        'output',
        'Player controller',
        'player',
        680,
        320,
        inputs: {'velocity': 'core.number'},
        output: 'core.object',
      ),
    ],
    edges: [
      DemoEdge('input', 'gate', 'pressed'),
      DemoEdge('grounded', 'gate', 'grounded'),
      DemoEdge('gate', 'impulse', 'enabled'),
      DemoEdge('impulse', 'output', 'velocity'),
    ],
  ),
  GraphDemo(
    id: 'workflow',
    category: 'Workflow & process',
    title: 'A decision with a clear path.',
    description:
        'Route an expense through a simple approval rule. Change the amount and see the decision change.',
    hint: 'Set the expense above the approval limit to require a review.',
    icon: Icons.account_tree_outlined,
    color: Color(0xff6fd9ba),
    nodes: [
      DemoNode(
        'expense',
        'Expense request',
        'number',
        0,
        80,
        fields: [DemoField('value', 'Amount (€)', 240.0, max: 2000)],
      ),
      DemoNode(
        'limit',
        'Approval policy',
        'number',
        0,
        280,
        fields: [
          DemoField('value', 'Auto-approve below (€)', 500.0, max: 2000),
        ],
      ),
      DemoNode(
        'decision',
        'Within budget?',
        'less',
        340,
        130,
        inputs: {'amount': 'core.number', 'limit': 'core.number'},
        output: 'core.boolean',
      ),
      DemoNode(
        'output',
        'Route request',
        'approval',
        680,
        130,
        inputs: {'approved': 'core.boolean'},
        output: 'core.object',
      ),
    ],
    edges: [
      DemoEdge('expense', 'decision', 'amount'),
      DemoEdge('limit', 'decision', 'limit'),
      DemoEdge('decision', 'output', 'approved'),
    ],
  ),
  GraphDemo(
    id: 'shader',
    category: 'Shader & material',
    title: 'Connect a little atmosphere.',
    description:
        'Turn coordinates into an animated material. The graph generates a fragment shader and runs it in WebGL.',
    hint: 'Change the wave frequency, speed, or palette hues, then run.',
    icon: Icons.gradient_outlined,
    color: Color(0xfff4b788),
    nodes: [
      DemoNode('uv', 'Texture coordinates', 'uv', 0, 80, output: 'demo.uv'),
      DemoNode(
        'wave',
        'Sine wave',
        'wave',
        340,
        80,
        inputs: {'uv': 'demo.uv'},
        output: 'demo.scalar',
        fields: [
          DemoField('frequency', 'Frequency', 8.0, min: 1, max: 20),
          DemoField('speed', 'Animation speed', 1.0, max: 4),
        ],
      ),
      DemoNode(
        'palette',
        'Color palette',
        'palette',
        340,
        340,
        inputs: {'factor': 'demo.scalar'},
        output: 'demo.color',
        fields: [
          DemoField('hueA', 'First hue', 260.0, max: 360),
          DemoField('hueB', 'Second hue', 22.0, max: 360),
        ],
      ),
      DemoNode(
        'output',
        'Material output',
        'surface',
        680,
        340,
        inputs: {'color': 'demo.color'},
        output: 'core.object',
      ),
    ],
    edges: [
      DemoEdge('uv', 'wave', 'uv'),
      DemoEdge('wave', 'palette', 'factor'),
      DemoEdge('palette', 'output', 'color'),
    ],
  ),
  GraphDemo(
    id: 'data',
    category: 'Dataflow & ETL',
    title: 'Make the useful data flow.',
    description:
        'Filter a small dataset, normalize its scores, and build a report. Every row is processed in your browser.',
    hint: 'Raise the minimum score to see fewer rows reach the report.',
    icon: Icons.stacked_line_chart_outlined,
    color: Color(0xff8bc9ff),
    nodes: [
      DemoNode(
        'rows',
        'Read dataset',
        'rows',
        0,
        80,
        output: 'core.array',
        fields: [
          DemoField('rows', 'Dataset (JSON)', [
            {'name': 'Ada', 'score': 92},
            {'name': 'Lin', 'score': 68},
            {'name': 'Sam', 'score': 47},
            {'name': 'Mika', 'score': 81},
          ]),
        ],
      ),
      DemoNode(
        'filter',
        'Filter scores',
        'filter',
        340,
        80,
        inputs: {'rows': 'core.array'},
        output: 'core.array',
        fields: [DemoField('minimum', 'Minimum score', 60.0, max: 100)],
      ),
      DemoNode(
        'normalize',
        'Normalize',
        'normalize',
        340,
        340,
        inputs: {'rows': 'core.array'},
        output: 'core.array',
      ),
      DemoNode(
        'output',
        'Build report',
        'report',
        680,
        340,
        inputs: {'rows': 'core.array'},
        output: 'core.object',
      ),
    ],
    edges: [
      DemoEdge('rows', 'filter', 'rows'),
      DemoEdge('filter', 'normalize', 'rows'),
      DemoEdge('normalize', 'output', 'rows'),
    ],
  ),
  GraphDemo(
    id: 'ml',
    category: 'ML architecture',
    title: 'Peek inside a tiny network.',
    description:
        'Run a real forward pass: a two-feature input, dense layers, ReLU, and a sigmoid classifier. No training or services.',
    hint: 'Edit the input vector or layer weights and compare the probability.',
    icon: Icons.hub_outlined,
    color: Color(0xfff3a6c8),
    nodes: [
      DemoNode(
        'features',
        'Input · 2 features',
        'vector',
        0,
        80,
        output: 'core.array',
        fields: [
          DemoField('values', 'Feature vector', [0.8, 0.3]),
        ],
      ),
      DemoNode(
        'hidden',
        'Dense · 2 units',
        'dense',
        340,
        80,
        inputs: {'vector': 'core.array'},
        output: 'core.array',
        fields: [
          DemoField('weights', 'Weights', [
            [0.9, -0.4],
            [0.2, 0.8],
          ]),
          DemoField('bias', 'Bias', [0.1, -0.1]),
        ],
      ),
      DemoNode(
        'relu',
        'ReLU activation',
        'relu',
        680,
        80,
        inputs: {'vector': 'core.array'},
        output: 'core.array',
      ),
      DemoNode(
        'classifier',
        'Dense · 1 unit',
        'dense',
        340,
        340,
        inputs: {'vector': 'core.array'},
        output: 'core.array',
        fields: [
          DemoField('weights', 'Weights', [
            [1.2, -0.7],
          ]),
          DemoField('bias', 'Bias', [0.05]),
        ],
      ),
      DemoNode(
        'output',
        'Sigmoid classifier',
        'sigmoid',
        680,
        340,
        inputs: {'vector': 'core.array'},
        output: 'core.object',
      ),
    ],
    edges: [
      DemoEdge('features', 'hidden', 'vector'),
      DemoEdge('hidden', 'relu', 'vector'),
      DemoEdge('relu', 'classifier', 'vector', [
        GraphPoint(975, 132),
        GraphPoint(975, 285),
        GraphPoint(300, 285),
        GraphPoint(300, 392),
      ]),
      DemoEdge('classifier', 'output', 'vector'),
    ],
  ),
  GraphDemo(
    id: 'audio',
    category: 'Modular audio',
    title: 'Patch something you can hear.',
    description:
        'A small synthesizer patch: oscillator → gain → low-pass filter → speaker. Play a quiet, two-second note.',
    hint:
        'Try a sawtooth wave and lower the filter cutoff. Audio starts only when you press Play.',
    icon: Icons.graphic_eq_outlined,
    color: Color(0xffe9cf81),
    nodes: [
      DemoNode(
        'oscillator',
        'Oscillator',
        'oscillator',
        0,
        80,
        output: 'demo.audio',
        fields: [
          DemoField('frequency', 'Frequency (Hz)', 220.0, min: 40, max: 1000),
          DemoField(
            'waveform',
            'Waveform',
            'sine',
            choices: ['sine', 'triangle', 'sawtooth', 'square'],
          ),
        ],
      ),
      DemoNode(
        'gain',
        'Gain',
        'gain',
        340,
        80,
        inputs: {'signal': 'demo.audio'},
        output: 'demo.audio',
        fields: [DemoField('gain', 'Level', 0.08, max: 0.2)],
      ),
      DemoNode(
        'filter',
        'Low-pass filter',
        'lowpass',
        340,
        340,
        inputs: {'signal': 'demo.audio'},
        output: 'demo.audio',
        fields: [DemoField('cutoff', 'Cutoff (Hz)', 900.0, min: 80, max: 5000)],
      ),
      DemoNode(
        'output',
        'Speaker',
        'speaker',
        680,
        340,
        inputs: {'signal': 'demo.audio'},
        output: 'core.object',
      ),
    ],
    edges: [
      DemoEdge('oscillator', 'gain', 'signal'),
      DemoEdge('gain', 'filter', 'signal'),
      DemoEdge('filter', 'output', 'signal'),
    ],
  ),
  GraphDemo(
    id: 'mindmap',
    category: 'Graph-based UI',
    title: 'Give your thoughts some space.',
    description:
        'An editable project map with shared dependencies. Rename an idea, add a branch, or reconnect the hierarchy.',
    hint:
        'Select an idea to rename it. Add a node, then connect it to a parent.',
    icon: Icons.bubble_chart_outlined,
    color: Color(0xffa9d98a),
    output: 'idea',
    nodes: [
      DemoNode(
        'idea',
        'The next big idea',
        'idea',
        0,
        220,
        inputs: {'parent': 'core.object'},
        output: 'core.object',
        fields: [DemoField('label', 'Idea', 'A better creative tool')],
      ),
      DemoNode(
        'interface',
        'Experience',
        'idea',
        340,
        20,
        inputs: {'parent': 'core.object'},
        output: 'core.object',
        fields: [DemoField('label', 'Idea', 'An intuitive experience')],
      ),
      DemoNode(
        'engine',
        'Foundations',
        'idea',
        340,
        400,
        inputs: {'parent': 'core.object'},
        output: 'core.object',
        fields: [DemoField('label', 'Idea', 'A dependable foundation')],
      ),
      DemoNode(
        'canvas',
        'Direct manipulation',
        'idea',
        680,
        0,
        inputs: {'parent': 'core.object'},
        output: 'core.object',
        fields: [DemoField('label', 'Idea', 'Make the canvas feel natural')],
      ),
      DemoNode(
        'history',
        'Undo everything',
        'idea',
        680,
        210,
        inputs: {'parent': 'core.object'},
        output: 'core.object',
        fields: [DemoField('label', 'Idea', 'Let people explore safely')],
      ),
      DemoNode(
        'types',
        'Clear contracts',
        'idea',
        680,
        420,
        inputs: {'parent': 'core.object'},
        output: 'core.object',
        fields: [DemoField('label', 'Idea', 'Keep connections meaningful')],
      ),
    ],
    edges: [
      DemoEdge('idea', 'interface', 'parent'),
      DemoEdge('idea', 'engine', 'parent'),
      DemoEdge('interface', 'canvas', 'parent'),
      DemoEdge('interface', 'history', 'parent'),
      DemoEdge('engine', 'types', 'parent'),
    ],
  ),
];
