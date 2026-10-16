import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes_example/main.dart';

void main() {
  testWidgets('example mounts the graph and round-trips new document JSON', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const GraphExampleApp());
    await tester.pumpAndSettle();
    expect(find.text('Dynamic switch'), findsOneWidget);
    await tester.tap(find.text('JSON'));
    await tester.pumpAndSettle();
    expect(find.text('Graph document JSON'), findsOneWidget);
    await tester.tap(find.text('Load document'));
    await tester.pumpAndSettle();
    expect(find.text('Dynamic switch'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
