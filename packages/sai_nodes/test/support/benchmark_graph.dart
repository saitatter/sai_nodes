import 'package:sai_nodes_core/sai_nodes_core.dart';

GraphDocument benchmarkDocument(int count) => GraphDocument(
  id: 'benchmark',
  spaces: {
    'main': GraphSpace(
      id: 'main',
      nodes: {
        for (var i = 0; i < count; i++)
          'n$i': GraphNode(
            id: 'n$i',
            type: i % 10 == 0 ? 'dynamic' : 'number',
            data: {'value': i, 'ports': 2},
          ),
      },
      connections: {
        for (var i = 1; i < count; i++)
          'e$i': GraphConnection(
            id: 'e$i',
            from: PortRef(nodeId: 'n${i - 1}', portId: 'value.out'),
            to: PortRef(nodeId: 'n$i', portId: 'value.in'),
            kind: GraphConnectionKind.data,
          ),
      },
      nodePresentations: {
        for (var i = 0; i < count; i++)
          'n$i': NodePresentation(
            nodeId: 'n$i',
            position: GraphPoint((i % 50) * 320, (i ~/ 50) * 180),
          ),
      },
    ),
  },
);
NodeDefinitionRegistry benchmarkDefinitions() {
  final definitions = NodeDefinitionRegistry();
  final ports = StaticPortFamily([
    ResolvedPort(
      id: 'value.in',
      direction: GraphPortDirection.input,
      kind: GraphPortKind.data,
      dataType: 'core.number',
      label: 'Value',
      maxConnections: 1,
    ),
    ResolvedPort(
      id: 'value.out',
      direction: GraphPortDirection.output,
      kind: GraphPortKind.data,
      dataType: 'core.number',
      label: 'Value',
    ),
  ]);
  definitions.register(
    DeclarativeNodeDefinition(
      type: 'number',
      displayName: 'Number',
      ports: [ports],
    ),
  );
  definitions.register(
    DeclarativeNodeDefinition(
      type: 'dynamic',
      displayName: 'Dynamic',
      ports: [
        ports,
        DynamicPortFamily(
          (context) => [
            for (var i = 0; i < (context.node.data['ports'] as int? ?? 0); i++)
              ResolvedPort(
                id: 'extra:$i',
                direction: GraphPortDirection.output,
                kind: GraphPortKind.data,
                label: '$i',
                dataType: 'core.number',
              ),
          ],
        ),
      ],
    ),
  );
  return definitions;
}

Map<String, Object> summary(List<double> values) {
  final sorted = [...values]..sort();
  return {
    'median': sorted[sorted.length ~/ 2],
    'p95':
        sorted[((sorted.length * .95).ceil() - 1).clamp(0, sorted.length - 1)],
    'samples': values,
  };
}
