import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';
import 'package:sai_nodes_example/gallery/app.dart';
import 'package:sai_nodes_example/gallery/catalog.dart';
import 'package:sai_nodes_example/gallery/session.dart';
import 'package:sai_nodes_example/gallery/idea_card.dart';

void main() {
  Future<void> open(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const GalleryApp());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'all seven examples show an editable canvas and evaluate their graph',
    (tester) async {
      await open(tester, const Size(1440, 960));
      for (final demo in graphDemos) {
        await tester.tap(find.byKey(ValueKey('demo-${demo.id}')));
        await tester.pumpAndSettle();
        expect(find.text(demo.title), findsOneWidget);
        final editor = tester.widget<NodeEditor>(find.byType(NodeEditor));
        expect(editor.controller.resolution.diagnostics, isEmpty);
        if (demo.isStructural) {
          expect(find.byKey(const ValueKey('run-demo')), findsNothing);
          expect(editor.executionSource, isNull);
          expect(find.textContaining('Live map'), findsWidgets);
          expect(find.byType(IdeaCard), findsWidgets);
          expect(tester.takeException(), isNull);
          continue;
        }
        await tester.tap(find.byKey(const ValueKey('run-demo')));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        if (demo.id == 'audio') {
          expect(
            find.text('Audio playback is available in the web gallery.'),
            findsOneWidget,
          );
        } else if (demo.mode == DemoMode.render) {
          expect(find.text('WebGL material preview'), findsOneWidget);
          expect(editor.executionSource, isNull);
        } else {
          expect(
            find.textContaining('nodes evaluated locally'),
            findsOneWidget,
            reason: demo.id,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'properties, run, undo, redo, add, delete and source errors preserve editing',
    (tester) async {
      await open(tester, const Size(1440, 960));
      await tester.tap(find.byKey(const ValueKey('node-picker-game-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grounded?').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('field-grounded-value')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('run-demo')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.text('Staying grounded.'), findsOneWidget);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      final graph = tester
          .widget<NodeEditor>(find.byType(NodeEditor))
          .controller;
      expect(graph.activeSpace!.nodes['grounded']!.data['value'], true);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      expect(graph.activeSpace!.nodes['grounded']!.data['value'], false);
      await tester.tap(find.byTooltip('Add node'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jump input').last);
      await tester.pumpAndSettle();
      expect(graph.activeSpace!.nodes.length, 6);
      await tester.ensureVisible(find.text('Delete selected'));
      await tester.tap(find.text('Delete selected'));
      await tester.pumpAndSettle();
      expect(graph.activeSpace!.nodes.length, 5);
      final before = graph.document;
      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('json-editor')), '{');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unexpected'), findsWidgets);
      expect(graph.document, same(before));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [
    const Size(390, 844),
    const Size(1024, 768),
    const Size(1440, 600),
  ]) {
    testWidgets('responsive gallery fits $size and exposes preview controls', (
      tester,
    ) async {
      await open(tester, size);
      if (size.width < 1180) {
        await tester.tap(find.byTooltip('Preview and properties'));
        await tester.pumpAndSettle();
        expect(find.text('PREVIEW'), findsOneWidget);
        expect(find.text('NODE PROPERTIES'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  test(
    'structural edits and undo refresh the outline without execution',
    () async {
      final demo = graphDemos.singleWhere((demo) => demo.isStructural);
      final session = GallerySession(demo);
      addTearDown(session.dispose);
      final node = session.graph.activeSpace!.nodes['idea']!;
      final field = demo.specFor(node).fields.single;
      session.update(node, field, 'An edited idea');
      expect((session.result!.value as Map)['label'], 'An edited idea');
      expect(session.visuals.snapshot.nodes, isEmpty);
      expect(session.running, false);
      session.graph.undo();
      expect((session.result!.value as Map)['label'], node.data['label']);
      await session.run();
      expect(session.visuals.snapshot.nodes, isEmpty);
      expect(session.visuals.snapshot.connections, isEmpty);
      expect(session.running, false);
    },
  );
  test('rendering has no execution trace or authoring mutation', () async {
    final demo = graphDemos.singleWhere((demo) => demo.mode == DemoMode.render);
    final session = GallerySession(demo);
    addTearDown(session.dispose);
    final document = session.graph.document;
    await session.run();
    expect(session.result, isNotNull);
    expect(session.graph.document, same(document));
    expect(session.visuals.snapshot.nodes, isEmpty);
    expect(session.running, false);
  });
  test(
    'stopping a run prevents delayed traces and malformed import is atomic',
    () async {
      final session = GallerySession(graphDemos.first);
      addTearDown(session.dispose);
      final run = session.run();
      session.stop();
      await run;
      expect(session.running, false);
      expect(session.visuals.snapshot.nodes, isEmpty);
      final before = session.graph.document;
      expect(() => session.loadJson('{'), throwsFormatException);
      expect(session.graph.document, same(before));
    },
  );
}
