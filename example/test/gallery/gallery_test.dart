import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';
import 'package:sai_nodes_example/gallery/app.dart';
import 'package:sai_nodes_example/gallery/catalog.dart';
import 'package:sai_nodes_example/gallery/session.dart';

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
        await tester.tap(find.byKey(const ValueKey('run-demo')));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        if (demo.id == 'audio') {
          expect(
            find.text('Audio playback is available in the web gallery.'),
            findsOneWidget,
          );
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
