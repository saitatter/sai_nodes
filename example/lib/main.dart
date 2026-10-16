import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sai_nodes/sai_nodes.dart';

void main() => runApp(const GraphExampleApp());

class GraphExampleApp extends StatelessWidget {
  const GraphExampleApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const GraphExample(),
  );
}

class GraphExample extends StatefulWidget {
  const GraphExample({super.key});
  @override
  State<GraphExample> createState() => _GraphExampleState();
}

class _GraphExampleState extends State<GraphExample> {
  late final GraphController controller;
  final visuals = GraphExecutionVisualController();
  final canvas = GlobalKey<NodeEditorState>();
  bool replay = false;
  @override
  void initState() {
    super.initState();
    final definitions = NodeDefinitionRegistry();
    final inputs = StaticPortFamily([
      ResolvedPort(
        id: 'value.in',
        direction: GraphPortDirection.input,
        kind: GraphPortKind.data,
        label: 'Value',
        dataType: 'core.number',
        maxConnections: 1,
      ),
      ResolvedPort(
        id: 'value.out',
        direction: GraphPortDirection.output,
        kind: GraphPortKind.data,
        label: 'Value',
        dataType: 'core.number',
      ),
    ]);
    definitions.register(
      DeclarativeNodeDefinition(
        type: 'number',
        displayName: 'Number',
        ports: [inputs],
        fields: [
          StaticFieldFamily([
            ResolvedField(
              id: 'value',
              label: 'Value',
              kind: GraphFieldKind.number,
            ),
          ]),
        ],
      ),
    );
    definitions.register(
      DeclarativeNodeDefinition(
        type: 'switch',
        displayName: 'Dynamic switch',
        visualStyle: const NodeVisualStyle(color: 0xffeab308),
        ports: [
          inputs,
          DynamicPortFamily(
            (context) => [
              for (final item
                  in (context.node.data['cases'] as List? ?? [])
                      .whereType<Map>())
                ResolvedPort(
                  id: 'case:${item['id']}',
                  direction: GraphPortDirection.output,
                  kind: GraphPortKind.data,
                  label: '${item['label']}',
                  dataType: 'core.number',
                ),
            ],
          ),
        ],
        fields: [
          StaticFieldFamily([
            ResolvedField(
              id: 'cases',
              label: 'Cases (JSON)',
              kind: GraphFieldKind.json,
            ),
          ]),
        ],
      ),
    );
    controller = GraphController(
      document: GraphDocument(
        id: 'example',
        spaces: {
          'main': GraphSpace(
            id: 'main',
            nodes: {
              'source': GraphNode(
                id: 'source',
                type: 'number',
                data: {'value': 42},
              ),
              'switch': GraphNode(
                id: 'switch',
                type: 'switch',
                data: {
                  'cases': [
                    {'id': 'one', 'label': 'One'},
                    {'id': 'two', 'label': 'Two'},
                  ],
                },
              ),
            },
            nodePresentations: {
              'source': NodePresentation(
                nodeId: 'source',
                position: const GraphPoint(80, 100),
              ),
              'switch': NodePresentation(
                nodeId: 'switch',
                position: const GraphPoint(440, 180),
              ),
            },
            connections: {
              'wire': GraphConnection(
                id: 'wire',
                from: const PortRef(nodeId: 'source', portId: 'value.out'),
                to: const PortRef(nodeId: 'switch', portId: 'value.in'),
                kind: GraphConnectionKind.data,
              ),
            },
          ),
        },
      ),
      resolver: GraphResolver(
        definitions: definitions,
        types: GraphTypeSystem.core(),
      ),
    );
    controller.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(changed);
    controller.dispose();
    visuals.dispose();
    super.dispose();
  }

  Future<GraphNode?> pick(GraphNodePickerRequest request) async {
    final type = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(200, 100, 200, 100),
      items: controller.resolver.definitions.definitions.values
          .map(
            (definition) => PopupMenuItem(
              value: definition.type,
              child: Text(definition.type),
            ),
          )
          .toList(),
    );
    return type == null
        ? null
        : GraphNode(
            id: newGraphId(),
            type: type,
            data: type == 'number'
                ? {'value': 0}
                : {
                    'cases': [
                      {'id': newGraphId(), 'label': 'Case'},
                    ],
                  },
          );
  }

  Future<void> add() async {
    final point = controller.camera.viewportToWorld(const GraphPoint(160, 160));
    final node = await pick(GraphNodePickerRequest(position: point));
    if (node != null && mounted) {
      controller.execute(
        AddNodeCommand(
          controller.activeSpaceId!,
          node,
          presentation: NodePresentation(nodeId: node.id, position: point),
        ),
        label: 'Add node',
      );
    }
  }

  Future<void> jsonDialog() async {
    final result = await showDialog<GraphDocument>(
      context: context,
      builder: (context) => _GraphJsonDialog(document: controller.document),
    );
    if (result != null && mounted) controller.replaceDocument(result);
  }

  void trace() {
    replay = !replay;
    if (!replay) {
      visuals.clear();
      return;
    }
    visuals.apply(
      GraphExecutionSnapshot(
        executionId: 'synthetic-example',
        nodes: {
          for (final node in controller.activeSpace!.nodes.values)
            ScopedNodeRef(
              controller.activeSpaceId!,
              node.id,
            ): NodeExecutionVisual(
              status: GraphExecutionStatus.running,
              activeCount: 1,
              invocationCount: 3,
              duration: const Duration(milliseconds: 120),
            ),
        },
        connections: {
          for (final edge in controller.activeSpace!.connections.values)
            ScopedConnectionRef(
              controller.activeSpaceId!,
              edge.id,
            ): const ConnectionExecutionVisual(
              active: true,
              traversalCount: 3,
            ),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Sai Nodes 1.0${controller.isDirty ? ' •' : ''}'),
      actions: [
        IconButton(
          tooltip: 'Add node',
          onPressed: add,
          icon: const Icon(Icons.add),
        ),
        IconButton(
          tooltip: 'Undo',
          onPressed: controller.canUndo ? controller.undo : null,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: 'Redo',
          onPressed: controller.canRedo ? controller.redo : null,
          icon: const Icon(Icons.redo),
        ),
        IconButton(
          tooltip: 'Fit graph',
          onPressed: () => canvas.currentState?.focusSelection(),
          icon: const Icon(Icons.center_focus_strong),
        ),
        TextButton(onPressed: jsonDialog, child: const Text('JSON')),
        TextButton(
          onPressed: controller.markSaved,
          child: const Text('Mark saved'),
        ),
        TextButton(
          onPressed: () {
            trace();
            setState(() {});
          },
          child: Text(replay ? 'Clear trace' : 'Simulate trace'),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: NodeEditor(
            key: canvas,
            controller: controller,
            onCreateNode: pick,
            executionSource: visuals,
          ),
        ),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Text(
            'Revision ${controller.revision} · semantic ${controller.semanticRevision} · ${controller.selection.nodes.length} selected · ${controller.resolution.diagnostics.length} diagnostics · right-click for actions',
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _GraphJsonDialog extends StatefulWidget {
  const _GraphJsonDialog({required this.document});
  final GraphDocument document;
  @override
  State<_GraphJsonDialog> createState() => _GraphJsonDialogState();
}

class _GraphJsonDialogState extends State<_GraphJsonDialog> {
  late final TextEditingController text;
  String? error;
  @override
  void initState() {
    super.initState();
    text = TextEditingController(
      text: const JsonEncoder.withIndent(
        '  ',
      ).convert(widget.document.toJson()),
    );
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Graph document JSON'),
    content: SizedBox(
      width: 700,
      height: 480,
      child: TextField(
        controller: text,
        maxLines: null,
        expands: true,
        decoration: InputDecoration(errorText: error),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          try {
            final value = jsonDecode(text.text);
            if (value is! Map<String, dynamic>) {
              throw const FormatException('Expected an object.');
            }
            Navigator.pop(context, GraphDocument.fromJson(value));
          } catch (problem) {
            setState(() => error = '$problem');
          }
        },
        child: const Text('Load document'),
      ),
    ],
  );
}
