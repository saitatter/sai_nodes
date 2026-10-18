import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sai_nodes/sai_nodes.dart';
import 'browser.dart';
import 'catalog.dart';
import 'runtime.dart';

class GallerySession extends ChangeNotifier {
  GallerySession(this.demo) : graph = demo.controller() {
    _semantic = graph.semanticRevision;
    graph.addListener(_changed);
    _evaluate();
  }
  final GraphDemo demo;
  final GraphController graph;
  final visuals = GraphExecutionVisualController();
  DemoRun? result;
  String? error;
  bool running = false;
  int _generation = 0, _semantic = 0;

  void _changed() {
    if (_semantic != graph.semanticRevision) {
      _semantic = graph.semanticRevision;
      stop();
      result = null;
      error = null;
    }
    notifyListeners();
  }

  bool _evaluate() {
    try {
      final errors = graph.resolution.diagnostics.where(
        (issue) => issue.severity == GraphDiagnosticSeverity.error,
      );
      if (errors.isNotEmpty) throw StateError(errors.first.message);
      result = DemoRuntime(demo, graph.document).run();
      error = null;
      return true;
    } catch (problem) {
      result = null;
      error = problem.toString().replaceFirst('Bad state: ', '');
      return false;
    }
  }

  Future<void> run({bool audio = false}) async {
    stop();
    if (!_evaluate()) {
      notifyListeners();
      return;
    }
    if (audio && demo.id == 'audio') {
      error = playDemoAudio(result!.value as Map);
      if (error != null) {
        notifyListeners();
        return;
      }
    }
    final generation = ++_generation;
    final run = result!;
    running = true;
    notifyListeners();
    final nodes = <ScopedNodeRef, NodeExecutionVisual>{};
    final connections = <ScopedConnectionRef, ConnectionExecutionVisual>{};
    for (final id in run.visited) {
      if (generation != _generation) return;
      nodes[ScopedNodeRef(gallerySpace, id)] = NodeExecutionVisual(
        status: GraphExecutionStatus.running,
        activeCount: 1,
        invocationCount: 1,
      );
      for (final edge in graph.activeSpace!.connections.values.where(
        (edge) => run.connections.contains(edge.id) && edge.to.nodeId == id,
      )) {
        connections[ScopedConnectionRef(gallerySpace, edge.id)] =
            const ConnectionExecutionVisual(active: true, traversalCount: 1);
      }
      visuals.apply(
        GraphExecutionSnapshot(
          nodes: nodes,
          connections: connections,
          executionId: 'demo:$generation',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 130));
      if (generation != _generation) return;
      nodes[ScopedNodeRef(gallerySpace, id)] = NodeExecutionVisual(
        status: GraphExecutionStatus.completed,
        invocationCount: 1,
      );
    }
    visuals.apply(
      GraphExecutionSnapshot(
        nodes: nodes,
        connections: {
          for (final entry in connections.entries)
            entry.key: const ConnectionExecutionVisual(traversalCount: 1),
        },
      ),
    );
    running = false;
    notifyListeners();
  }

  void stop() {
    _generation++;
    running = false;
    stopDemoAudio();
    visuals.clear();
  }

  void reset() {
    stop();
    graph.replaceDocument(demo.document());
    _evaluate();
    notifyListeners();
  }

  void update(GraphNode node, DemoField field, Object value) => graph.execute(
    UpdateNodeDataCommand(gallerySpace, node.id, {
      field.id: value,
    }, merge: true),
  );

  void loadJson(String source) {
    if (source.length > 200000) {
      throw const FormatException('Keep demo documents under 200 KB.');
    }
    final json = jsonDecode(source);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Expected a graph document object.');
    }
    final document = GraphDocument.fromJson(json);
    if (document.spaces.length != 1 ||
        !document.spaces.containsKey(gallerySpace)) {
      throw const FormatException('This demo uses a single main space.');
    }
    final space = document.spaces[gallerySpace]!;
    if (space.nodes.length > 100 || space.connections.length > 200) {
      throw const FormatException(
        'Limit the demo to 100 nodes and 200 connections.',
      );
    }
    for (final node in space.nodes.values) {
      demo.specFor(node);
    }
    stop();
    graph.replaceDocument(document);
    _evaluate();
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    graph.removeListener(_changed);
    graph.dispose();
    visuals.dispose();
    super.dispose();
  }
}
