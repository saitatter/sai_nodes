import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';

void main() {
  test('menu filtering keeps matching descendants and removes edge dividers',
      () {
    const entries = <NodeEditorMenuEntry>[
      NodeEditorMenuDivider(),
      NodeEditorMenuSection(
        label: 'Create',
        entries: [
          NodeEditorMenuDivider(),
          NodeEditorMenuAction(label: 'Trigger'),
          NodeEditorMenuDivider(),
          NodeEditorMenuAction(label: 'Action'),
          NodeEditorMenuDivider(),
        ],
      ),
      NodeEditorMenuDivider(),
    ];

    final filtered = filterNodeEditorMenuEntries(entries, 'action');

    expect(filtered, hasLength(1));
    final section = filtered.single as NodeEditorMenuSection;
    expect(section.label, 'Create');
    expect(section.entries, hasLength(1));
    expect((section.entries.single as NodeEditorMenuAction).label, 'Action');
  });

  test('menu filtering preserves dividers between matching actions', () {
    final filtered = filterNodeEditorMenuEntries(
      const [
        NodeEditorMenuAction(label: 'First action'),
        NodeEditorMenuDivider(),
        NodeEditorMenuAction(label: 'Second action'),
      ],
      'action',
    );

    expect(filtered, hasLength(3));
    expect(filtered[1], isA<NodeEditorMenuDivider>());
  });

  testWidgets('menu collapses sections and selects enabled actions',
      (tester) async {
    var selected = false;
    final entries = <NodeEditorMenuEntry>[
      NodeEditorMenuSection(
        label: 'Group',
        entries: [
          NodeEditorMenuAction(
            label: 'Run action',
            onSelected: () => selected = true,
          ),
        ],
      ),
      const NodeEditorMenuAction(label: 'Disabled', enabled: false),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NodeEditorContextMenu(
            entries: entries,
            searchable: false,
            closeOnSelect: false,
          ),
        ),
      ),
    );

    expect(find.text('Run action'), findsOneWidget);
    await tester.tap(find.text('Group'));
    await tester.pump();
    expect(find.text('Run action'), findsNothing);

    await tester.tap(find.text('Group'));
    await tester.pump();
    await tester.tap(find.text('Run action'));
    expect(selected, isTrue);

    await tester.tap(find.text('Disabled'));
    expect(selected, isTrue);
  });

  testWidgets('menu search shows matching actions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NodeEditorContextMenu(
            entries: [
              NodeEditorMenuAction(label: 'Create node'),
              NodeEditorMenuAction(label: 'Paste selection'),
            ],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'paste');
    await tester.pump();

    expect(find.text('Paste selection'), findsOneWidget);
    expect(find.text('Create node'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('Create node'), findsOneWidget);
  });

  testWidgets('menu supports keyboard traversal and skips disabled actions',
      (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NodeEditorContextMenu(
            searchable: false,
            closeOnSelect: false,
            entries: [
              const NodeEditorMenuAction(
                label: 'Disabled',
                enabled: false,
              ),
              NodeEditorMenuAction(
                label: 'First action',
                onSelected: () => selected = 'first',
              ),
              NodeEditorMenuAction(
                label: 'Second action',
                onSelected: () => selected = 'second',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(selected, 'second');
  });

  test('gradient link styles survive copyWith', () {
    const gradient = LinearGradient(
      colors: [Colors.blue, Colors.green],
    );
    const style = LinkStyle.gradient(
      gradient: gradient,
      lineWidth: 2,
      drawMode: LineDrawMode.solid,
      curveType: LinkCurveType.bezier,
    );

    final copy = style.copyWith(lineWidth: 4);

    expect(copy.gradient, same(gradient));
    expect(copy.color, isNull);
    expect(copy.lineWidth, 4);
  });
}
