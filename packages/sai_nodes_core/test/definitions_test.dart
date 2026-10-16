import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:test/test.dart';

ResolvedPort port(
  String id,
  GraphPortDirection direction, {
  String type = 'core.number',
  int? max,
}) => ResolvedPort(
  id: id,
  direction: direction,
  kind: GraphPortKind.data,
  label: id,
  dataType: type,
  maxConnections: max,
);

void main() {
  late NodeDefinitionRegistry definitions;
  late GraphResolver resolver;
  GraphDocument document({List<String> cases = const ['one', 'two']}) =>
      GraphDocument(
        id: 'd',
        spaces: {
          'main': GraphSpace(
            id: 'main',
            nodes: {
              'switch': GraphNode(
                id: 'switch',
                type: 'switch',
                data: {'cases': cases},
              ),
              'target': GraphNode(id: 'target', type: 'target'),
            },
            connections: {
              'wire': GraphConnection(
                id: 'wire',
                from: const PortRef(nodeId: 'switch', portId: 'case:one'),
                to: const PortRef(nodeId: 'target', portId: 'value.in'),
                kind: GraphConnectionKind.data,
              ),
            },
          ),
        },
      );
  setUp(() {
    definitions = NodeDefinitionRegistry();
    definitions.register(
      DeclarativeNodeDefinition(
        type: 'switch',
        displayName: 'Switch',
        ports: [
          DynamicPortFamily(
            (context) => (context.node.data['cases'] as List)
                .cast<String>()
                .map((id) => port('case:$id', GraphPortDirection.output)),
          ),
        ],
        fields: [
          DynamicFieldFamily(
            (context) => [
              for (final id in context.node.data['cases'] as List)
                ResolvedField(
                  id: 'field:$id',
                  label: '$id',
                  kind: GraphFieldKind.string,
                ),
            ],
          ),
        ],
      ),
    );
    definitions.register(
      DeclarativeNodeDefinition(
        type: 'target',
        displayName: 'Target',
        ports: [
          StaticPortFamily([
            port('value.in', GraphPortDirection.input, max: 1),
          ]),
        ],
      ),
    );
    resolver = GraphResolver(
      definitions: definitions,
      types: GraphTypeSystem.core(),
    );
  });
  test('dynamic ports and fields resolve from data and retain stable IDs', () {
    final initial = resolver.resolve(document());
    expect(initial.converged, true);
    expect(initial.diagnostics, isEmpty);
    expect(
      initial.structures['main']!['switch']!.ports.map((port) => port.id),
      ['case:one', 'case:two'],
    );
    expect(
      initial.structures['main']!['switch']!.fields.map((field) => field.id),
      ['field:one', 'field:two'],
    );
    final edited = resolver.resolve(document(cases: ['two', 'three']));
    expect(
      edited.diagnostics.map((issue) => issue.code),
      contains('missing-source-port'),
    );
    expect(edited.document.spaces['main']!.connections.keys, ['wire']);
    expect(
      edited.structures['main']!['switch']!.port('case:two')!.id,
      'case:two',
    );
  });
  test(
    'definition replacement invalidates registry without prototype recreation',
    () {
      var changes = 0;
      definitions.addListener(() => changes++);
      definitions.register(
        DeclarativeNodeDefinition(
          type: 'target',
          displayName: 'Changed',
          ports: [
            StaticPortFamily([
              port('value.in', GraphPortDirection.input, type: 'core.string'),
            ]),
          ],
        ),
        replace: true,
      );
      expect(changes, 1);
      expect(
        resolver.resolve(document()).diagnostics.map((issue) => issue.code),
        contains('type-mismatch'),
      );
      expect(
        () => definitions.register(
          DeclarativeNodeDefinition(type: 'target', displayName: 'Duplicate'),
        ),
        throwsArgumentError,
      );
      definitions.unregister('target');
      final missing = resolver.resolve(document());
      expect(
        missing.diagnostics.map((issue) => issue.code),
        contains('missing-definition'),
      );
      expect(missing.document, document());
    },
  );
  test(
    'removal policy is explicit and reconciles presentations in one result',
    () {
      final pruning = GraphResolver(
        definitions: definitions,
        types: GraphTypeSystem.core(),
        invalidConnectionPolicy: InvalidConnectionPolicy.remove,
      );
      final result = pruning.resolve(document(cases: ['two']));
      expect(result.converged, true);
      expect(result.document.spaces['main']!.connections, isEmpty);
      expect(result.diagnostics, isEmpty);
    },
  );
  test('dependent structures converge across multiple bounded passes', () {
    definitions.register(
      DeclarativeNodeDefinition(
        type: 'dependent',
        displayName: 'Dependent',
        ports: [
          DynamicPortFamily(
            (context) => context.structures['switch']?.ports ?? [],
          ),
        ],
      ),
    );
    final source = document();
    final space = source.spaces['main']!;
    final result = resolver.resolve(
      source.copyWith(
        spaces: {
          'main': space.copyWith(
            nodes: {
              ...space.nodes,
              'dependent': GraphNode(id: 'dependent', type: 'dependent'),
            },
          ),
        },
      ),
    );
    expect(result.converged, true);
    expect(result.passes, greaterThanOrEqualTo(3));
    expect(result.structures['main']!['dependent']!.ports.length, 2);
  });
  test(
    'oscillating definitions report nonconvergence without changing data',
    () {
      definitions.register(
        DeclarativeNodeDefinition(
          type: 'oscillating',
          displayName: 'Oscillating',
          ports: [
            DynamicPortFamily(
              (context) =>
                  context.structures[context.node.id]?.ports.isNotEmpty == true
                  ? []
                  : [port('flip', GraphPortDirection.output)],
            ),
          ],
        ),
      );
      final source = GraphDocument(
        id: 'd',
        spaces: {
          'main': GraphSpace(
            id: 'main',
            nodes: {'n': GraphNode(id: 'n', type: 'oscillating')},
          ),
        },
      );
      final result = resolver.resolve(source);
      expect(result.converged, false);
      expect(result.passes, 16);
      expect(
        result.diagnostics.map((issue) => issue.code),
        contains('non-converging-definition'),
      );
      expect(result.document, source);
    },
  );
  test(
    'duplicate ports across directions are diagnosed as resolution errors',
    () {
      definitions.register(
        DeclarativeNodeDefinition(
          type: 'target',
          displayName: 'Invalid',
          ports: [
            StaticPortFamily([
              port('same', GraphPortDirection.input),
              port('same', GraphPortDirection.output),
            ]),
          ],
        ),
        replace: true,
      );
      expect(
        resolver.resolve(document()).diagnostics.map((issue) => issue.code),
        contains('resolution-error'),
      );
    },
  );
  test('direction and cardinality violations retain all connections', () {
    final source = document();
    final space = source.spaces['main']!;
    final extra = space.connections['wire']!;
    final result = resolver.resolve(
      source.copyWith(
        spaces: {
          'main': space.copyWith(
            connections: {
              ...space.connections,
              'second': GraphConnection(
                id: 'second',
                from: extra.from,
                to: extra.to,
                kind: extra.kind,
              ),
            },
          ),
        },
      ),
    );
    expect(
      result.diagnostics
          .where((issue) => issue.code == 'max-connections')
          .length,
      2,
    );
    expect(result.document.spaces['main']!.connections.length, 2);
    definitions.register(
      DeclarativeNodeDefinition(
        type: 'target',
        displayName: 'Wrong direction',
        ports: [
          StaticPortFamily([port('value.in', GraphPortDirection.output)]),
        ],
      ),
      replace: true,
    );
    expect(
      resolver.resolve(source).diagnostics.map((issue) => issue.code),
      contains('wrong-port-direction'),
    );
  });
}
