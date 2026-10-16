import 'package:sai_nodes_core/sai_nodes_core.dart';

sealed class GraphInteraction {
  const GraphInteraction();
}

final class GraphIdle extends GraphInteraction {
  const GraphIdle();
}

final class GraphPanning extends GraphInteraction {
  const GraphPanning(this.origin, this.camera);
  final GraphPoint origin;
  final GraphCamera camera;
}

final class GraphDraggingNodes extends GraphInteraction {
  GraphDraggingNodes(this.origin, Map<String, GraphPoint> positions)
    : positions = Map.unmodifiable(positions);
  final GraphPoint origin;
  final Map<String, GraphPoint> positions;
  final Object session = Object();
}

final class GraphMarquee extends GraphInteraction {
  const GraphMarquee(this.origin, this.additive);
  final GraphPoint origin;
  final bool additive;
}

final class GraphConnecting extends GraphInteraction {
  const GraphConnecting(this.fixed, {this.connectionId});
  final PortRef fixed;
  final String? connectionId;
}

final class GraphDraggingWaypoint extends GraphInteraction {
  GraphDraggingWaypoint(this.connectionId, this.index);
  final String connectionId;
  final int index;
  final Object session = Object();
}

final class GraphDraggingFrame extends GraphInteraction {
  GraphDraggingFrame(this.frameId, this.origin);
  final String frameId;
  GraphPoint origin;
  final Object session = Object();
}

final class GraphDraggingComment extends GraphInteraction {
  GraphDraggingComment(this.commentId, this.origin, this.bounds);
  final String commentId;
  final GraphPoint origin;
  final GraphRect bounds;
  final Object session = Object();
}

enum GraphResizeKind { node, frame, comment }

final class GraphResizing extends GraphInteraction {
  GraphResizing(this.kind, this.id, this.origin, this.bounds);
  final GraphResizeKind kind;
  final String id;
  final GraphPoint origin;
  final GraphRect bounds;
  final Object session = Object();
}
