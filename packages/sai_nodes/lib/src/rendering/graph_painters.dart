import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../scene/graph_scene.dart';
import '../theme/graph_editor_theme.dart';

Offset graphOffset(GraphPoint point) => Offset(point.x, point.y);
Rect graphRect(GraphRect rect) =>
    Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height);
void graphTransform(Canvas canvas, GraphCamera camera) {
  canvas.translate(camera.offset.x, camera.offset.y);
  canvas.scale(camera.zoom);
}

GraphRect graphViewport(Size size, GraphCamera camera, {double margin = 0}) {
  final origin = camera.viewportToWorld(GraphPoint.zero);
  return GraphRect(
    origin.x,
    origin.y,
    size.width / camera.zoom,
    size.height / camera.zoom,
  ).inflate(margin);
}

Path connectionPath(ConnectionGeometry geometry) {
  final path = Path();
  if (geometry.points.isEmpty) return path;
  path.moveTo(geometry.points.first.x, geometry.points.first.y);
  for (final point in geometry.points.skip(1)) {
    path.lineTo(point.x, point.y);
  }
  return path;
}

void paintGraphText(
  Canvas canvas,
  String text,
  GraphPoint position,
  Color color, {
  double size = 11,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: size),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: 260);
  painter.paint(canvas, graphOffset(position));
}

final class GraphGridPainter extends CustomPainter {
  GraphGridPainter(this.camera, this.theme);
  final GraphCamera camera;
  final GraphEditorTheme theme;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.background);
    var spacing = 24 * camera.zoom;
    while (spacing < 12) {
      spacing *= 2;
    }
    final paint = Paint()
      ..color = theme.grid
      ..strokeWidth = 1;
    final x = camera.offset.x % spacing, y = camera.offset.y % spacing;
    for (var dx = x; dx < size.width; dx += spacing) {
      for (var dy = y; dy < size.height; dy += spacing) {
        canvas.drawCircle(Offset(dx, dy), .75, paint);
      }
    }
  }

  @override
  bool shouldRepaint(GraphGridPainter old) =>
      old.camera != camera || old.theme != theme;
}

final class GraphConnectionPainter extends CustomPainter {
  GraphConnectionPainter(
    this.scene,
    this.camera,
    this.selection,
    this.theme, {
    this.hovered,
  });
  final GraphScene scene;
  final GraphCamera camera;
  final GraphSelection selection;
  final GraphEditorTheme theme;
  final String? hovered;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    graphTransform(canvas, camera);
    final visible = scene.connectionIndex.query(
      graphViewport(size, camera, margin: 30),
    );
    for (final id in visible) {
      final edge = scene.connections[id]!;
      final selected = selection.connections.contains(id);
      final color = edge.invalid
          ? theme.error
          : selected || hovered == id
          ? theme.selected
          : edge.connection.kind == GraphConnectionKind.control
          ? theme.control
          : theme.data;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = theme.connectionWidth + (selected ? 1 : 0)
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(connectionPath(edge.geometry), paint);
      final end = edge.geometry.pointAt(1),
          previous = edge.geometry.pointAt(.98),
          angle = math.atan2(end.y - previous.y, end.x - previous.x);
      final arrow = Path()
        ..moveTo(end.x, end.y)
        ..lineTo(
          end.x - 10 * math.cos(angle - .4),
          end.y - 10 * math.sin(angle - .4),
        )
        ..moveTo(end.x, end.y)
        ..lineTo(
          end.x - 10 * math.cos(angle + .4),
          end.y - 10 * math.sin(angle + .4),
        );
      canvas.drawPath(arrow, paint);
      final label = edge.label;
      if (label != null && label.isNotEmpty) {
        final point =
            edge.geometry.pointAt(.5) +
            (edge.presentation.labelOffset ?? const GraphPoint(5, -18));
        paintGraphText(canvas, label, point, color);
      }
      if (selected) {
        for (final point in edge.presentation.waypoints) {
          canvas.drawCircle(
            graphOffset(point),
            5,
            Paint()..color = theme.selected,
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GraphConnectionPainter old) =>
      old.scene != scene ||
      old.camera != camera ||
      old.selection != selection ||
      old.theme != theme ||
      old.hovered != hovered;
}

final class GraphSelectionPainter extends CustomPainter {
  GraphSelectionPainter(
    this.scene,
    this.camera,
    this.selection,
    this.theme, {
    this.marquee,
    this.guides = const [],
  });
  final GraphScene scene;
  final GraphCamera camera;
  final GraphSelection selection;
  final GraphEditorTheme theme;
  final GraphRect? marquee;
  final List<(GraphPoint, GraphPoint)> guides;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    graphTransform(canvas, camera);
    final border = Paint()
      ..color = theme.selected
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / camera.zoom;
    for (final id in selection.nodes) {
      final rect = scene.nodes[id]?.geometry.bounds;
      if (rect != null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            graphRect(rect.inflate(2)),
            Radius.circular(theme.cornerRadius),
          ),
          border,
        );
      }
    }
    for (final id in selection.frames) {
      final frame = scene.space.frames[id];
      if (frame != null) {
        canvas.drawRect(graphRect(frame.bounds.inflate(2)), border);
      }
    }
    for (final id in selection.comments) {
      final comment = scene.space.comments[id];
      if (comment != null) {
        canvas.drawRect(graphRect(comment.bounds.inflate(2)), border);
      }
    }
    if (marquee != null) {
      canvas.drawRect(
        graphRect(marquee!),
        Paint()..color = theme.selected.withValues(alpha: .12),
      );
      canvas.drawRect(graphRect(marquee!), border);
    }
    for (final guide in guides) {
      canvas.drawLine(graphOffset(guide.$1), graphOffset(guide.$2), border);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GraphSelectionPainter old) => true;
}

final class GraphExecutionPainter extends CustomPainter {
  GraphExecutionPainter(
    this.scene,
    this.camera,
    this.source,
    this.animation,
    this.theme,
    Listenable repaint,
  ) : super(repaint: repaint);
  final GraphScene scene;
  final GraphCamera camera;
  final GraphExecutionVisualSource? source;
  final Animation<double> animation;
  final GraphEditorTheme theme;
  @override
  void paint(Canvas canvas, Size size) {
    final snapshot = source?.snapshot;
    if (snapshot == null) return;
    canvas.save();
    graphTransform(canvas, camera);
    for (final entry in snapshot.nodes.entries) {
      if (entry.key.spaceId != scene.spaceId) continue;
      final node = scene.nodes[entry.key.nodeId];
      if (node == null) continue;
      final visual = entry.value;
      final color = visual.status == GraphExecutionStatus.error
          ? theme.error
          : visual.status == GraphExecutionStatus.aborted
          ? Colors.orange
          : theme.running;
      final paint = Paint()
        ..color = color.withValues(
          alpha: visual.activeCount > 0
              ? 0.65 + 0.3 * math.sin(animation.value * math.pi * 2)
              : 0.7,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          graphRect(node.geometry.bounds.inflate(4)),
          const Radius.circular(10),
        ),
        paint,
      );
      paintGraphText(
        canvas,
        '${visual.invocationCount}× · ${visual.duration.inMilliseconds} ms${visual.error == null ? '' : ' · ${visual.error}'}',
        GraphPoint(node.geometry.bounds.left, node.geometry.bounds.bottom + 7),
        color,
      );
    }
    for (final entry in snapshot.connections.entries) {
      if (entry.key.spaceId != scene.spaceId) continue;
      final edge = scene.connections[entry.key.connectionId];
      if (edge == null) continue;
      canvas.drawPath(
        connectionPath(edge.geometry),
        Paint()
          ..color = theme.running.withValues(alpha: .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      if (entry.value.active) {
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(
            graphOffset(edge.geometry.pointAt((animation.value + i / 3) % 1)),
            3.5,
            Paint()..color = theme.running,
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GraphExecutionPainter old) =>
      old.scene != scene ||
      old.camera != camera ||
      old.source != source ||
      old.theme != theme;
}

final class GraphInteractionPainter extends CustomPainter {
  GraphInteractionPainter(this.camera, this.theme, {this.from, this.to});
  final GraphCamera camera;
  final GraphEditorTheme theme;
  final GraphPoint? from, to;
  @override
  void paint(Canvas canvas, Size size) {
    if (from == null || to == null) return;
    canvas.save();
    graphTransform(canvas, camera);
    canvas.drawPath(
      connectionPath(const ConnectionGeometryEngine().compute(from!, to!)),
      Paint()
        ..color = theme.selected
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(GraphInteractionPainter old) => true;
}
