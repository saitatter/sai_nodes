import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../interaction/graph_interaction.dart';
import '../rendering/graph_painters.dart';
import '../scene/graph_scene.dart';
import '../theme/graph_editor_theme.dart';

typedef GraphNodeWidgetBuilder =
    Widget Function(BuildContext, GraphNodeViewModel);
typedef GraphPortWidgetBuilder =
    Widget Function(BuildContext, GraphNodeViewModel, ResolvedPort);
typedef GraphFieldWidgetBuilder =
    Widget Function(
      BuildContext,
      GraphNodeViewModel,
      ResolvedField,
      Object?,
      ValueChanged<Object?>,
    );

final class GraphNodePickerRequest {
  const GraphNodePickerRequest({
    required this.position,
    this.port,
    this.connectionId,
  });
  final GraphPoint position;
  final PortRef? port;
  final String? connectionId;
}

/// Generic Flutter canvas. Semantic actions and document persistence belong to the host.
class NodeEditor extends StatefulWidget {
  const NodeEditor({
    super.key,
    required this.controller,
    this.nodeBuilder,
    this.headerBuilder,
    this.portLabelBuilder,
    this.portBuilder,
    this.fieldBuilder,
    this.frameBuilder,
    this.commentBuilder,
    this.contextMenuBuilder,
    this.overlays = const [],
    this.onCreateNode,
    this.onError,
    this.executionSource,
    this.theme = const GraphEditorTheme(),
    this.routing = ConnectionRouting.bezier,
    this.virtualize = true,
    this.overscan = 160,
    this.showMinimap = true,
    this.snapToGrid = false,
    this.gridSize = 24,
    this.connectionLabel,
    this.captureFragment,
    this.pasteFragment,
  });
  final GraphController controller;
  final GraphNodeWidgetBuilder? nodeBuilder;
  final GraphNodeWidgetBuilder? headerBuilder;
  final GraphPortWidgetBuilder? portLabelBuilder;
  final GraphPortWidgetBuilder? portBuilder;
  final GraphFieldWidgetBuilder? fieldBuilder;
  final Widget Function(BuildContext, GraphFrame)? frameBuilder;
  final Widget Function(BuildContext, GraphComment)? commentBuilder;
  final Future<void> Function(BuildContext, GraphPoint, GraphScene)?
  contextMenuBuilder;
  final List<Widget> overlays;
  final Future<GraphNode?> Function(GraphNodePickerRequest)? onCreateNode;
  final ValueChanged<String>? onError;
  final GraphExecutionVisualSource? executionSource;
  final GraphEditorTheme theme;
  final ConnectionRouting routing;
  final bool virtualize, showMinimap, snapToGrid;
  final double overscan, gridSize;
  final String? Function(GraphConnection)? connectionLabel;

  /// Host payload and dependency handling shared by shortcuts and context menus.
  final GraphFragment Function()? captureFragment;
  final void Function(GraphFragment fragment)? pasteFragment;
  @override
  State<NodeEditor> createState() => NodeEditorState();
}

class NodeEditorState extends State<NodeEditor> with TickerProviderStateMixin {
  final _focus = FocusNode(debugLabel: 'Graph canvas');
  final _builder = GraphSceneBuilder();
  final _executionRepaint = ValueNotifier<int>(0);
  final _focusedNodes = <String>{};
  final _contents = <String, (GraphNodeViewModel, Widget)>{};
  final _pointers = <int, Offset>{};
  late final AnimationController _animation;
  late final Ticker _scrollTicker;
  GraphScene? _scene;
  GraphResolution? _lastResolution;
  GraphInteraction _interaction = const GraphIdle();
  GraphPoint _pointer = GraphPoint.zero;
  GraphPoint? _doubleTapPosition;
  GraphPoint? _lastTapPosition;
  DateTime? _lastTapTime;
  GraphPoint? _downPosition;
  bool _primaryPointer = true;
  Size _size = Size.zero;
  String? _hoveredEdge;
  Duration? _lastScroll;
  List<(GraphPoint, GraphPoint)> _guides = [];
  GraphCamera? _pinchCamera;
  Offset? _pinchCenter;
  double _pinchDistance = 0;
  GraphCamera? _trackpadCamera;
  GraphController get controller => widget.controller;
  GraphScene get scene => _scene ??= _builder.build(
    controller,
    routing: widget.routing,
    connectionLabel: widget.connectionLabel,
  );
  GraphPoint _point(Offset point) => GraphPoint(point.dx, point.dy);
  GraphPoint _world(Offset point) =>
      controller.camera.viewportToWorld(_point(point));
  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _scrollTicker = createTicker(_autoScroll);
    controller.addListener(_changed);
    widget.executionSource?.addListener(_executionChanged);
    _executionChanged();
  }

  @override
  void didUpdateWidget(NodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_changed);
      controller.addListener(_changed);
      _contents.clear();
      _scene = null;
      _lastResolution = null;
    }
    if (oldWidget.executionSource != widget.executionSource) {
      oldWidget.executionSource?.removeListener(_executionChanged);
      widget.executionSource?.addListener(_executionChanged);
      _executionChanged();
    }
    if (oldWidget.routing != widget.routing ||
        oldWidget.connectionLabel != widget.connectionLabel ||
        oldWidget.nodeBuilder != widget.nodeBuilder ||
        oldWidget.headerBuilder != widget.headerBuilder ||
        oldWidget.portLabelBuilder != widget.portLabelBuilder ||
        oldWidget.fieldBuilder != widget.fieldBuilder) {
      _scene = null;
      _contents.clear();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_lastResolution != controller.resolution ||
        _scene?.spaceId != controller.activeSpaceId) {
      _scene = null;
      _lastResolution = controller.resolution;
    }
    setState(() {});
  }

  void _executionChanged() {
    final snapshot = widget.executionSource?.snapshot;
    final active =
        snapshot?.nodes.values.any((node) => node.activeCount > 0) == true ||
        snapshot?.connections.values.any((edge) => edge.active) == true;
    if (active && !_animation.isAnimating) {
      _animation.repeat();
    } else if (!active) {
      _animation.stop();
    }
    _executionRepaint.value++;
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    widget.executionSource?.removeListener(_executionChanged);
    _focus.dispose();
    _animation.dispose();
    _executionRepaint.dispose();
    _scrollTicker.dispose();
    super.dispose();
  }

  void _perform(void Function() action) {
    try {
      action();
    } catch (error) {
      if (widget.onError != null) {
        widget.onError!('$error');
      } else if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  bool get _additive =>
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;
  (GraphNodeViewModel, ResolvedPort)? _hitPort(GraphPoint world) {
    final tolerance = 12 / controller.camera.zoom;
    for (final id in scene.nodeIndex.query(
      GraphRect(
        world.x - tolerance,
        world.y - tolerance,
        tolerance * 2,
        tolerance * 2,
      ),
    )) {
      final node = scene.nodes[id]!;
      for (final port in node.structure?.ports ?? <ResolvedPort>[]) {
        if (node.geometry.ports[port.id]!.distanceTo(world) <= tolerance) {
          return (node, port);
        }
      }
    }
    return null;
  }

  void _start(GraphInteraction interaction) {
    _interaction = interaction;
    _lastScroll = null;
    if (interaction is! GraphPanning && !_scrollTicker.isActive) {
      _scrollTicker.start();
    }
    setState(() {});
  }

  void _pointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (event.kind == PointerDeviceKind.touch && _pointers.length == 2) {
      final pair = _pointers.values.toList();
      _pinchCamera = controller.camera;
      _pinchCenter = (pair[0] + pair[1]) / 2;
      _pinchDistance = (pair[0] - pair[1]).distance;
      _interaction = const GraphIdle();
      _scrollTicker.stop();
      return;
    }
    if (_pointers.length > 1) return;
    _pointer = _point(event.localPosition);
    _downPosition = _pointer;
    _primaryPointer = event.buttons != kSecondaryMouseButton;
    if (event.buttons == kSecondaryMouseButton) return;
    if (event.buttons == kMiddleMouseButton ||
        HardwareKeyboard.instance.isLogicalKeyPressed(
          LogicalKeyboardKey.space,
        )) {
      _focus.requestFocus();
      _start(GraphPanning(_pointer, controller.camera));
      return;
    }
    final world = _world(event.localPosition), sid = controller.activeSpaceId;
    if (sid == null) return;
    final port = _hitPort(world);
    if (port != null) {
      _focus.requestFocus();
      final ref = PortRef(nodeId: port.$1.node.id, portId: port.$2.id);
      final existing = controller.indexes[sid]?.connectionIdsByPort[ref] ?? {};
      if (existing.isNotEmpty &&
          (port.$2.direction == GraphPortDirection.input ||
              HardwareKeyboard.instance.isAltPressed)) {
        final edge = controller.activeSpace!.connections[existing.first]!;
        _start(
          GraphConnecting(
            port.$2.direction == GraphPortDirection.input ? edge.from : edge.to,
            connectionId: edge.id,
          ),
        );
      } else {
        _start(GraphConnecting(ref));
      }
      return;
    }
    for (final id in controller.selection.connections) {
      final edge = scene.connections[id];
      if (edge == null) continue;
      for (final entry in edge.presentation.waypoints.indexed) {
        if (entry.$2.distanceTo(world) < 10 / controller.camera.zoom) {
          _focus.requestFocus();
          _start(GraphDraggingWaypoint(id, entry.$1));
          return;
        }
      }
    }
    final node = scene.hitNode(world);
    if (node != null) {
      if (_additive) {
        controller.toggleNode(node.node.id);
      } else if (!controller.selection.nodes.contains(node.node.id)) {
        controller.select(GraphSelection(nodes: {node.node.id}));
      }
      final rect = node.geometry.bounds;
      if (world.x > rect.right - 12 && world.y > rect.bottom - 12) {
        _focus.requestFocus();
        _start(GraphResizing(GraphResizeKind.node, node.node.id, world, rect));
        return;
      }
      if (world.y < rect.top + _builder.nodes.headerHeight) {
        _focus.requestFocus();
        _start(
          GraphDraggingNodes(world, {
            for (final id in controller.selection.nodes)
              id: scene.nodes[id]!.presentation.position,
          }),
        );
      }
      return;
    }
    final edge = scene.hitConnection(
      world,
      tolerance: 8 / controller.camera.zoom,
    );
    if (edge != null) {
      _focus.requestFocus();
      controller.select(GraphSelection(connections: {edge.connection.id}));
      return;
    }
    for (final comment in scene.space.comments.values.toList().reversed) {
      if (!comment.bounds.contains(world)) continue;
      _focus.requestFocus();
      controller.select(GraphSelection(comments: {comment.id}));
      _start(
        world.x > comment.bounds.right - 12 &&
                world.y > comment.bounds.bottom - 12
            ? GraphResizing(
                GraphResizeKind.comment,
                comment.id,
                world,
                comment.bounds,
              )
            : GraphDraggingComment(comment.id, world, comment.bounds),
      );
      return;
    }
    for (final frame in scene.space.frames.values.toList().reversed) {
      if (!frame.bounds.contains(world)) continue;
      if (world.x > frame.bounds.right - 12 &&
          world.y > frame.bounds.bottom - 12) {
        controller.select(GraphSelection(frames: {frame.id}));
        _start(
          GraphResizing(GraphResizeKind.frame, frame.id, world, frame.bounds),
        );
        return;
      }
      if (world.y < frame.bounds.top + 28) {
        _focus.requestFocus();
        controller.select(GraphSelection(frames: {frame.id}));
        _start(GraphDraggingFrame(frame.id, world));
        return;
      }
    }
    _focus.requestFocus();
    if (!_additive) controller.select(GraphSelection());
    _start(GraphMarquee(world, _additive));
  }

  void _pointerMove(PointerMoveEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pinchCamera != null && _pointers.length >= 2) {
      final pair = _pointers.values.take(2).toList(),
          center = (_pointers.values.first + _pointers.values.elementAt(1)) / 2;
      final factor = _pinchDistance == 0
          ? 1.0
          : (pair[0] - pair[1]).distance / _pinchDistance;
      final zoom = _pinchCamera!.zoomAt(_point(_pinchCenter!), factor);
      controller.setCamera(zoom.pan(_point(center - _pinchCenter!)));
      return;
    }
    _pointer = _point(event.localPosition);
    _updateInteraction();
  }

  void _updateInteraction() {
    final world = controller.camera.viewportToWorld(_pointer),
        sid = controller.activeSpaceId;
    if (sid == null) return;
    switch (_interaction) {
      case GraphPanning(:final origin, :final camera):
        controller.setCamera(camera.pan(_pointer - origin));
      case GraphDraggingNodes(:final origin, :final positions, :final session):
        var delta = world - origin;
        _guides = [];
        if (positions.isNotEmpty) {
          final first = positions.values.first + delta;
          if (widget.snapToGrid) {
            delta =
                GraphPoint(
                  (first.x / widget.gridSize).round() * widget.gridSize,
                  (first.y / widget.gridSize).round() * widget.gridSize,
                ) -
                positions.values.first;
          } else {
            var bestX = 6 / controller.camera.zoom, bestY = bestX;
            double? alignX, alignY;
            for (final node in scene.nodes.values) {
              if (positions.containsKey(node.node.id)) continue;
              final x = node.presentation.position.x,
                  y = node.presentation.position.y;
              if ((x - first.x).abs() < bestX) {
                bestX = (x - first.x).abs();
                alignX = x;
              }
              if ((y - first.y).abs() < bestY) {
                bestY = (y - first.y).abs();
                alignY = y;
              }
            }
            if (alignX != null) {
              delta = GraphPoint(alignX - positions.values.first.x, delta.y);
              _guides.add((
                GraphPoint(alignX, world.y - 1000),
                GraphPoint(alignX, world.y + 1000),
              ));
            }
            if (alignY != null) {
              delta = GraphPoint(delta.x, alignY - positions.values.first.y);
              _guides.add((
                GraphPoint(world.x - 1000, alignY),
                GraphPoint(world.x + 1000, alignY),
              ));
            }
          }
        }
        _perform(
          () => controller.execute(
            MoveNodesCommand(sid, {
              for (final entry in positions.entries)
                entry.key: entry.value + delta,
            }),
            label: 'Move nodes',
            coalesceKey: session,
          ),
        );
      case GraphDraggingWaypoint(
        :final connectionId,
        :final index,
        :final session,
      ):
        final view =
            controller.activeSpace!.connectionPresentations[connectionId] ??
            ConnectionPresentation(connectionId: connectionId);
        final points = [...view.waypoints];
        if (index < points.length) {
          points[index] = world;
          _perform(
            () => controller.execute(
              UpdateConnectionPresentationCommand(
                sid,
                view.copyWith(waypoints: points),
              ),
              label: 'Move waypoint',
              coalesceKey: session,
            ),
          );
        }
      case GraphDraggingFrame interaction:
        final delta = world - interaction.origin;
        interaction.origin = world;
        _perform(
          () => controller.moveFrameWithMembers(
            interaction.frameId,
            delta,
            coalesceKey: interaction.session,
          ),
        );
      case GraphDraggingComment(
        :final commentId,
        :final origin,
        :final bounds,
        :final session,
      ):
        final comment = controller.activeSpace!.comments[commentId];
        if (comment != null) {
          _perform(
            () => controller.execute(
              UpdateCommentCommand(
                sid,
                comment.copyWith(bounds: bounds.translate(world - origin)),
              ),
              label: 'Move comment',
              coalesceKey: session,
            ),
          );
        }
      case GraphResizing(
        :final kind,
        :final id,
        :final origin,
        :final bounds,
        :final session,
      ):
        final delta = world - origin;
        final size = GraphSize(
          math.max(100, bounds.width + delta.x),
          math.max(
            kind == GraphResizeKind.node ? 60 : 40,
            bounds.height + delta.y,
          ),
        );
        _perform(
          () => controller.transaction(
            (tx) {
              switch (kind) {
                case GraphResizeKind.node:
                  tx.execute(ResizeNodesCommand(sid, {id: size}));
                case GraphResizeKind.frame:
                  final frame = controller.activeSpace!.frames[id]!;
                  tx.execute(
                    UpdateFrameCommand(
                      sid,
                      frame.copyWith(
                        bounds: GraphRect(
                          bounds.left,
                          bounds.top,
                          size.width,
                          size.height,
                        ),
                      ),
                    ),
                  );
                case GraphResizeKind.comment:
                  final comment = controller.activeSpace!.comments[id]!;
                  tx.execute(
                    UpdateCommentCommand(
                      sid,
                      comment.copyWith(
                        bounds: GraphRect(
                          bounds.left,
                          bounds.top,
                          size.width,
                          size.height,
                        ),
                      ),
                    ),
                  );
              }
            },
            label: 'Resize ${kind.name}',
            coalesceKey: session,
          ),
        );
      case GraphMarquee():
        setState(() {});
      case GraphConnecting():
        setState(() {});
      case GraphIdle():
        break;
    }
  }

  void _autoScroll(Duration elapsed) {
    final previous = _lastScroll;
    _lastScroll = elapsed;
    if (previous == null || _interaction is GraphIdle) return;
    final dt = (elapsed - previous).inMicroseconds / 1000000;
    double velocity(double value, double extent) => value < 36
        ? (36 - value).clamp(0, 100) * 8
        : value > extent - 36
        ? -(value - extent + 36).clamp(0, 100) * 8
        : 0;
    final delta = GraphPoint(
      velocity(_pointer.x, _size.width) * dt,
      velocity(_pointer.y, _size.height) * dt,
    );
    if (delta != GraphPoint.zero) {
      controller.setCamera(controller.camera.pan(delta));
      _updateInteraction();
    }
  }

  void _pointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pinchCamera != null) {
      if (_pointers.isEmpty) {
        _pinchCamera = null;
        _pinchCenter = null;
      }
      return;
    }
    final interaction = _interaction;
    _scrollTicker.stop();
    _lastScroll = null;
    _guides = [];
    _interaction = const GraphIdle();
    if (event is PointerUpEvent) {
      _pointer = _point(event.localPosition);
      if (interaction is GraphMarquee) {
        final bounds = GraphRect.fromPoints(
          interaction.origin,
          controller.camera.viewportToWorld(_pointer),
        );
        controller.marquee(
          bounds,
          scene.nodes.map((id, node) => MapEntry(id, node.geometry.bounds)),
          additive: interaction.additive,
        );
      }
      if (interaction is GraphConnecting) {
        unawaited(
          _finishConnection(
            interaction,
            controller.camera.viewportToWorld(_pointer),
          ),
        );
      }
    }
    if (event is PointerUpEvent &&
        _primaryPointer &&
        _downPosition != null &&
        _downPosition!.distanceTo(_pointer) < 5) {
      final world = controller.camera.viewportToWorld(_pointer);
      final node = scene.hitNode(world);
      final onHeader =
          node != null &&
          world.y < node.geometry.bounds.top + _builder.nodes.headerHeight;
      if (onHeader ||
          (node == null &&
              (scene.hitConnection(world) != null ||
                  scene.space.comments.values.any(
                    (comment) => comment.bounds.contains(world),
                  )))) {
        final now = DateTime.now();
        if (_lastTapPosition != null &&
            _lastTapPosition!.distanceTo(_pointer) < 8 &&
            _lastTapTime != null &&
            now.difference(_lastTapTime!).inMilliseconds < 300) {
          _doubleTapPosition = world;
          _doubleTap();
          _lastTapTime = null;
          _lastTapPosition = null;
        } else {
          _lastTapTime = now;
          _lastTapPosition = _pointer;
        }
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _finishConnection(
    GraphConnecting interaction,
    GraphPoint point,
  ) async {
    final sid = controller.activeSpaceId;
    if (sid == null) return;
    final fixed = controller
        .resolution
        .structures[sid]?[interaction.fixed.nodeId]
        ?.port(interaction.fixed.portId);
    if (fixed == null) return;
    final hit = _hitPort(point);
    if (hit != null) {
      final target = PortRef(nodeId: hit.$1.node.id, portId: hit.$2.id);
      if (target == interaction.fixed || hit.$2.direction == fixed.direction) {
        return;
      }
      _perform(() => _connect(interaction, target, sid, fixed));
      return;
    }
    final picker = widget.onCreateNode;
    if (picker == null) return;
    final node = await picker(
      GraphNodePickerRequest(
        position: point,
        port: interaction.fixed,
        connectionId: interaction.connectionId,
      ),
    );
    if (node == null || !mounted || sid != controller.activeSpaceId) return;
    _perform(
      () => controller.transaction((tx) {
        tx.execute(
          AddNodeCommand(
            sid,
            node,
            presentation: NodePresentation(nodeId: node.id, position: point),
          ),
        );
        final structures = controller.resolver
            .resolve(tx.document)
            .structures[sid];
        final ports = structures?[node.id]?.ports.where(
          (port) =>
              port.direction != fixed.direction &&
              port.kind == fixed.kind &&
              (port.kind == GraphPortKind.control ||
                  controller.resolver.types.canConnect(
                    outputType: fixed.direction == GraphPortDirection.output
                        ? fixed.dataType
                        : port.dataType,
                    inputType: fixed.direction == GraphPortDirection.output
                        ? port.dataType
                        : fixed.dataType,
                  )),
        );
        if (ports == null || ports.isEmpty) {
          throw StateError('Selected node has no compatible port.');
        }
        _connect(
          interaction,
          PortRef(nodeId: node.id, portId: ports.first.id),
          sid,
          fixed,
          transaction: tx,
        );
      }, label: 'Create and connect node'),
    );
  }

  void _connect(
    GraphConnecting interaction,
    PortRef target,
    String sid,
    ResolvedPort fixed, {
    GraphTransaction? transaction,
  }) {
    final from = fixed.direction == GraphPortDirection.output
        ? interaction.fixed
        : target;
    final to = fixed.direction == GraphPortDirection.input
        ? interaction.fixed
        : target;
    final command = interaction.connectionId == null
        ? AddConnectionCommand(
            sid,
            GraphConnection(
              id: newGraphId(),
              from: from,
              to: to,
              kind: fixed.kind == GraphPortKind.control
                  ? GraphConnectionKind.control
                  : GraphConnectionKind.data,
            ),
          )
        : ReconnectConnectionCommand(
            sid,
            interaction.connectionId!,
            from: from,
            to: to,
          );
    if (transaction != null) {
      transaction.execute(command);
    } else {
      controller.execute(
        command,
        label: interaction.connectionId == null ? 'Connect ports' : 'Reconnect',
      );
    }
  }

  void _scroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isShiftPressed ||
        event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()) {
      controller.setCamera(
        controller.camera.pan(
          GraphPoint(-event.scrollDelta.dx, -event.scrollDelta.dy),
        ),
      );
    } else {
      controller.setCamera(
        controller.camera.zoomAt(
          _point(event.localPosition),
          math.exp(-event.scrollDelta.dy * .002),
        ),
      );
    }
  }

  bool _editingText() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    return context.findAncestorStateOfType<EditableTextState>() != null;
  }

  KeyEventResult _key(FocusNode focus, KeyEvent event) {
    if (event is! KeyDownEvent || _editingText()) return KeyEventResult.ignored;
    final key = event.logicalKey,
        modifier =
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
    if (key == LogicalKeyboardKey.escape) {
      _interaction = const GraphIdle();
      _scrollTicker.stop();
      controller.select(GraphSelection());
      setState(() {});
      return KeyEventResult.handled;
    }
    if (modifier && key == LogicalKeyboardKey.keyZ) {
      _perform(
        HardwareKeyboard.instance.isShiftPressed
            ? controller.redo
            : controller.undo,
      );
      return KeyEventResult.handled;
    }
    if (modifier && key == LogicalKeyboardKey.keyY) {
      _perform(controller.redo);
      return KeyEventResult.handled;
    }
    if (modifier && key == LogicalKeyboardKey.keyA) {
      controller.selectAll();
      return KeyEventResult.handled;
    }
    if (modifier &&
        (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.keyX)) {
      unawaited(_copy(cut: key == LogicalKeyboardKey.keyX));
      return KeyEventResult.handled;
    }
    if (modifier && key == LogicalKeyboardKey.keyV) {
      unawaited(_paste());
      return KeyEventResult.handled;
    }
    if (modifier && key == LogicalKeyboardKey.keyD) {
      _perform(() => _pasteFragment(_captureFragment()));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _perform(controller.deleteSelection);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      focusSelection();
      return KeyEventResult.handled;
    }
    if ([
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ].contains(key)) {
      final selected = controller.selection.nodes.firstOrNull;
      final origin =
          scene.nodes[selected]?.geometry.bounds.center ?? GraphPoint.zero;
      final direction = key == LogicalKeyboardKey.arrowLeft
          ? const GraphPoint(-1, 0)
          : key == LogicalKeyboardKey.arrowRight
          ? const GraphPoint(1, 0)
          : key == LogicalKeyboardKey.arrowUp
          ? const GraphPoint(0, -1)
          : const GraphPoint(0, 1);
      final candidates =
          scene.nodes.values.where((node) {
            final delta = node.geometry.bounds.center - origin;
            return node.node.id != selected &&
                delta.x * direction.x + delta.y * direction.y > 0;
          }).toList()..sort(
            (a, b) => a.geometry.bounds.center
                .distanceTo(origin)
                .compareTo(b.geometry.bounds.center.distanceTo(origin)),
          );
      if (candidates.isNotEmpty) {
        controller.select(GraphSelection(nodes: {candidates.first.node.id}));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _copy({bool cut = false}) async {
    final target = controller;
    final selected = controller.selection,
        revision = controller.revision,
        sid = controller.activeSpaceId;
    try {
      await Clipboard.setData(ClipboardData(text: _captureFragment().encode()));
      if (cut &&
          mounted &&
          identical(controller, target) &&
          controller.activeSpaceId == sid &&
          controller.revision == revision) {
        _perform(() => controller.deleteSelection(selected: selected));
      }
    } catch (error) {
      if (mounted) _perform(() => throw StateError('Clipboard failed: $error'));
    }
  }

  Future<void> _paste() async {
    final target = controller, spaceId = controller.activeSpaceId;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted ||
          !identical(controller, target) ||
          controller.activeSpaceId != spaceId ||
          data?.text == null) {
        return;
      }
      _perform(() => _pasteFragment(GraphFragment.decode(data!.text!)));
    } catch (error) {
      if (mounted) _perform(() => throw StateError('Clipboard failed: $error'));
    }
  }

  GraphFragment _captureFragment() =>
      widget.captureFragment?.call() ?? GraphFragment.capture(controller);
  void _pasteFragment(GraphFragment fragment) {
    if (widget.pasteFragment case final paste?) {
      paste(fragment);
    } else {
      controller.pasteGraphFragment(fragment);
    }
  }

  void focusSelection() => controller.focusNodes(
    controller.selection.nodes.isEmpty
        ? scene.nodes.keys
        : controller.selection.nodes,
    scene.nodes.map((id, node) => MapEntry(id, node.geometry.bounds)),
    GraphSize(_size.width, _size.height),
  );
  Future<void> _editText(
    String title,
    String initial,
    ValueChanged<String> save,
  ) async {
    final text = TextEditingController(text: initial);
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLines: title == 'Comment' ? 4 : 1,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    text.dispose();
    if (result != null && mounted) _perform(() => save(result));
  }

  void _doubleTap() {
    final point = _doubleTapPosition;
    if (point == null) return;
    final node = scene.hitNode(point), sid = controller.activeSpaceId;
    if (sid == null) return;
    if (node != null) {
      _perform(
        () => controller.execute(
          SetNodeCollapsedCommand(
            sid,
            node.node.id,
            !node.presentation.collapsed,
          ),
          label: 'Toggle collapsed',
        ),
      );
      return;
    }
    final edge = scene.hitConnection(
      point,
      tolerance: 10 / controller.camera.zoom,
    );
    if (edge != null) {
      final view = edge.presentation;
      _perform(
        () => controller.execute(
          UpdateConnectionPresentationCommand(
            sid,
            view.copyWith(waypoints: [...view.waypoints, point]),
          ),
          label: 'Add waypoint',
        ),
      );
      return;
    }
    for (final comment in scene.space.comments.values) {
      if (comment.bounds.contains(point)) {
        unawaited(
          _editText(
            'Comment',
            comment.text,
            (value) => controller.execute(
              UpdateCommentCommand(sid, comment.copyWith(text: value)),
              label: 'Edit comment',
            ),
          ),
        );
        return;
      }
    }
  }

  Future<void> _contextMenu(Offset local, Offset global) async {
    final point = _world(local), sid = controller.activeSpaceId;
    if (sid == null) return;
    if (widget.contextMenuBuilder != null) {
      await widget.contextMenuBuilder!(context, point, scene);
      return;
    }
    final node = scene.hitNode(point),
        edge = scene.hitConnection(
          point,
          tolerance: 10 / controller.camera.zoom,
        );
    final frame = scene.space.frames.values
        .where((frame) => frame.bounds.contains(point))
        .lastOrNull;
    if (node != null && !controller.selection.nodes.contains(node.node.id)) {
      controller.select(GraphSelection(nodes: {node.node.id}));
    } else if (node == null && edge != null) {
      controller.select(GraphSelection(connections: {edge.connection.id}));
    }
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        global.dx,
        global.dy,
        global.dx,
        global.dy,
      ),
      items: [
        if (edge != null && widget.onCreateNode != null)
          const PopupMenuItem(
            value: 'splice',
            child: Text('Insert node into connection'),
          ),
        if (widget.onCreateNode != null)
          const PopupMenuItem(value: 'create', child: Text('Add node')),
        if (node != null)
          const PopupMenuItem(value: 'rename', child: Text('Rename node')),
        if (node != null)
          const PopupMenuItem(
            value: 'disconnect',
            child: Text('Disconnect node'),
          ),
        if (edge != null)
          const PopupMenuItem(
            value: 'label',
            child: Text('Edit connection label'),
          ),
        if (edge != null)
          const PopupMenuItem(value: 'reset-route', child: Text('Reset route')),
        if (edge != null && edge.presentation.waypoints.isNotEmpty)
          const PopupMenuItem(
            value: 'remove-waypoint',
            child: Text('Remove nearest waypoint'),
          ),
        if (frame != null)
          const PopupMenuItem(
            value: 'rename-frame',
            child: Text('Rename frame'),
          ),
        if (frame != null)
          const PopupMenuItem(
            value: 'fit-frame',
            child: Text('Fit frame to members'),
          ),
        if (frame != null)
          const PopupMenuItem(
            value: 'auto-fit',
            child: Text('Toggle frame auto-fit'),
          ),
        if (!controller.selection.isEmpty)
          const PopupMenuItem(value: 'copy', child: Text('Copy selection')),
        const PopupMenuItem(value: 'paste', child: Text('Paste')),
        if (controller.selection.nodes.isNotEmpty)
          const PopupMenuItem(value: 'frame', child: Text('Frame selection')),
        const PopupMenuItem(value: 'comment', child: Text('Add comment')),
        if (!controller.selection.isEmpty)
          const PopupMenuItem(value: 'delete', child: Text('Delete selection')),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'splice':
        final picked = await widget.onCreateNode!(
          GraphNodePickerRequest(
            position: point,
            connectionId: edge!.connection.id,
          ),
        );
        if (picked != null && mounted) {
          _perform(
            () => controller.spliceNodeIntoConnection(
              edge.connection.id,
              picked,
              presentation: NodePresentation(
                nodeId: picked.id,
                position: point,
              ),
            ),
          );
        }
      case 'create':
        final picked = await widget.onCreateNode!(
          GraphNodePickerRequest(position: point),
        );
        if (picked != null && mounted) {
          _perform(
            () => controller.execute(
              AddNodeCommand(
                sid,
                picked,
                presentation: NodePresentation(
                  nodeId: picked.id,
                  position: point,
                ),
              ),
              label: 'Add node',
            ),
          );
        }
      case 'rename':
        unawaited(
          _editText(
            'Node title',
            node!.label,
            (value) => controller.execute(
              SetNodeTitleCommand(sid, node.node.id, value),
              label: 'Rename node',
            ),
          ),
        );
      case 'disconnect':
        _perform(() => controller.disconnectNode(node!.node.id));
      case 'label':
        unawaited(
          _editText(
            'Connection label',
            edge!.label ?? '',
            (value) => controller.execute(
              UpdateConnectionPresentationCommand(
                sid,
                edge.presentation.copyWith(label: value.isEmpty ? null : value),
              ),
              label: 'Edit label',
            ),
          ),
        );
      case 'reset-route':
        _perform(
          () => controller.execute(
            UpdateConnectionPresentationCommand(
              sid,
              edge!.presentation.copyWith(waypoints: []),
            ),
            label: 'Reset route',
          ),
        );
      case 'remove-waypoint':
        final points = [...edge!.presentation.waypoints];
        var nearest = 0;
        for (var i = 1; i < points.length; i++) {
          if (points[i].distanceTo(point) < points[nearest].distanceTo(point)) {
            nearest = i;
          }
        }
        points.removeAt(nearest);
        _perform(
          () => controller.execute(
            UpdateConnectionPresentationCommand(
              sid,
              edge.presentation.copyWith(waypoints: points),
            ),
            label: 'Remove waypoint',
          ),
        );
      case 'rename-frame':
        unawaited(
          _editText(
            'Frame title',
            frame!.title,
            (value) => controller.execute(
              UpdateFrameCommand(sid, frame.copyWith(title: value)),
              label: 'Rename frame',
            ),
          ),
        );
      case 'fit-frame':
        _perform(
          () => controller.fitFrame(
            frame!.id,
            scene.nodes.map((id, node) => MapEntry(id, node.geometry.bounds)),
          ),
        );
      case 'auto-fit':
        _perform(
          () => controller.execute(
            UpdateFrameCommand(sid, frame!.copyWith(autoFit: !frame.autoFit)),
            label: 'Toggle auto-fit',
          ),
        );
      case 'copy':
        await _copy();
      case 'paste':
        await _paste();
      case 'frame':
        final bounds = controller.selection.nodes
            .map((id) => scene.nodes[id]!.geometry.bounds)
            .reduce((a, b) => a.union(b));
        _perform(() => controller.createFrameFromSelection(bounds.inflate(24)));
      case 'comment':
        _perform(
          () => controller.execute(
            CreateCommentCommand(
              sid,
              GraphComment(
                id: newGraphId(),
                bounds: GraphRect(point.x, point.y, 220, 100),
                text: 'Comment',
              ),
            ),
            label: 'Add comment',
          ),
        );
      case 'delete':
        _perform(controller.deleteSelection);
    }
  }

  Object? _fieldValue(GraphNode node, ResolvedField field) {
    Object? value = node.data;
    for (final key in field.dataPath) {
      value = value is Map ? value[key] : null;
    }
    return value;
  }

  void _setField(GraphNodeViewModel node, ResolvedField field, Object? value) {
    final sid = controller.activeSpaceId;
    if (sid == null) return;
    GraphJson updated(GraphJson current, int depth) {
      final key = field.dataPath[depth];
      if (depth == field.dataPath.length - 1) return {...current, key: value};
      final nested = current[key];
      return {
        ...current,
        key: updated(
          nested is Map ? Map<String, Object?>.from(nested) : {},
          depth + 1,
        ),
      };
    }

    final current = controller.activeSpace!.nodes[node.node.id]!;
    _perform(
      () => controller.execute(
        UpdateNodeDataCommand(sid, node.node.id, updated(current.data, 0)),
        label: 'Edit ${field.label}',
        coalesceKey: 'field:${node.node.id}:${field.id}',
      ),
    );
  }

  Widget _nodeContents(GraphNodeViewModel node) {
    final cached = _contents[node.node.id];
    if (cached != null) {
      final old = cached.$1;
      if (old.node == node.node &&
          old.structure == node.structure &&
          old.label == node.label &&
          old.presentation.collapsed == node.presentation.collapsed &&
          old.geometry.bounds.width == node.geometry.bounds.width &&
          old.geometry.bounds.height == node.geometry.bounds.height &&
          old.unresolved == node.unresolved &&
          old.style.color == node.style.color) {
        return cached.$2;
      }
    }
    final content =
        widget.nodeBuilder?.call(context, node) ?? _defaultNode(node);
    _contents[node.node.id] = (node, content);
    return content;
  }

  Widget _defaultNode(GraphNodeViewModel node) {
    final ports = node.structure?.ports ?? [];
    final inputs = ports
        .where((port) => port.direction == GraphPortDirection.input)
        .toList();
    final outputs = ports
        .where((port) => port.direction == GraphPortDirection.output)
        .toList();
    final rows = math.max(inputs.length, outputs.length);
    final theme = widget.theme;
    return Material(
      color: theme.node,
      borderRadius: BorderRadius.circular(theme.cornerRadius),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: node.unresolved ? theme.error : theme.border,
          ),
          borderRadius: BorderRadius.circular(theme.cornerRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: _builder.nodes.headerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Color(node.style.color).withValues(alpha: .22),
                border: Border(
                  left: BorderSide(color: Color(node.style.color), width: 3),
                ),
              ),
              alignment: Alignment.centerLeft,
              child:
                  widget.headerBuilder?.call(context, node) ??
                  Text(
                    node.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            ),
            if (!node.presentation.collapsed) ...[
              for (var row = 0; row < rows; row++)
                SizedBox(
                  height: _builder.nodes.rowHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child:
                              row < inputs.length &&
                                  widget.portLabelBuilder != null
                              ? widget.portLabelBuilder!(
                                  context,
                                  node,
                                  inputs[row],
                                )
                              : Text(
                                  row < inputs.length ? inputs[row].label : '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: theme.text.withValues(alpha: .8),
                                    fontSize: 11,
                                  ),
                                ),
                        ),
                        Expanded(
                          child:
                              row < outputs.length &&
                                  widget.portLabelBuilder != null
                              ? widget.portLabelBuilder!(
                                  context,
                                  node,
                                  outputs[row],
                                )
                              : Text(
                                  row < outputs.length
                                      ? outputs[row].label
                                      : '',
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: theme.text.withValues(alpha: .8),
                                    fontSize: 11,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final field
                  in (node.structure?.fields ?? <ResolvedField>[]).where(
                    (field) => field.metadata['placement'] != 'inspector',
                  ))
                SizedBox(
                  height: _builder.nodes.fieldHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    child:
                        widget.fieldBuilder?.call(
                          context,
                          node,
                          field,
                          _fieldValue(node.node, field),
                          (value) => _setField(node, field, value),
                        ) ??
                        _GraphField(
                          key: ValueKey('${node.node.id}/${field.id}'),
                          field: field,
                          value: _fieldValue(node.node, field),
                          onChanged: (value) => _setField(node, field, value),
                          theme: theme,
                        ),
                  ),
                ),
              if (node.unresolved)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Unresolved definition',
                    style: TextStyle(color: theme.error, fontSize: 11),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _positioned(GraphRect bounds, Widget child, {Key? key}) {
    final position = controller.camera.worldToViewport(
      GraphPoint(bounds.left, bounds.top),
    );
    return Positioned(
      key: key,
      left: position.x,
      top: position.y,
      width: bounds.width * controller.camera.zoom,
      height: bounds.height * controller.camera.zoom,
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: bounds.width,
          height: bounds.height,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: _key,
    child: LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        final current = scene, camera = controller.camera;
        final visible = widget.virtualize
            ? current.nodeIndex.query(
                graphViewport(
                  _size,
                  camera,
                  margin: widget.overscan / camera.zoom,
                ),
              )
            : current.nodes.keys.toSet();
        visible.addAll(_focusedNodes.where(current.nodes.containsKey));
        if (_interaction case GraphDraggingNodes(:final positions)) {
          visible.addAll(positions.keys);
        }
        _contents.removeWhere((id, _) => !current.nodes.containsKey(id));
        final interaction = _interaction;
        GraphPoint? fixed;
        if (interaction is GraphConnecting) {
          fixed = current
              .nodes[interaction.fixed.nodeId]
              ?.geometry
              .ports[interaction.fixed.portId];
        }
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _pointerDown,
                onPointerMove: _pointerMove,
                onPointerUp: _pointerUp,
                onPointerCancel: _pointerUp,
                onPointerSignal: _scroll,
                onPointerHover: (event) {
                  final edge = current
                      .hitConnection(
                        _world(event.localPosition),
                        tolerance: 8 / camera.zoom,
                      )
                      ?.connection
                      .id;
                  if (edge != _hoveredEdge) setState(() => _hoveredEdge = edge);
                },
                onPointerPanZoomStart: (event) {
                  _trackpadCamera = controller.camera;
                },
                onPointerPanZoomUpdate: (event) {
                  final original = _trackpadCamera;
                  if (original != null) {
                    controller.setCamera(
                      original
                          .zoomAt(_point(event.localPosition), event.scale)
                          .pan(_point(event.pan)),
                    );
                  }
                },
                onPointerPanZoomEnd: (_) {
                  _trackpadCamera = null;
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onSecondaryTapUp: (details) => unawaited(
                    _contextMenu(details.localPosition, details.globalPosition),
                  ),
                  child: ClipRect(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: GraphGridPainter(camera, widget.theme),
                            ),
                          ),
                        ),
                        for (final frame in current.space.frames.values)
                          if (frame.bounds.isValid &&
                              frame.bounds.overlaps(
                                graphViewport(_size, camera),
                              ))
                            _positioned(
                              frame.bounds,
                              widget.frameBuilder?.call(context, frame) ??
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: widget.theme.frame.withValues(
                                        alpha: .08,
                                      ),
                                      border: Border.all(
                                        color: widget.theme.frame,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(
                                          frame.title,
                                          style: TextStyle(
                                            color: widget.theme.text,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              key: ValueKey('frame:${frame.id}'),
                            ),
                        for (final comment in current.space.comments.values)
                          if (comment.bounds.isValid &&
                              comment.bounds.overlaps(
                                graphViewport(_size, camera),
                              ))
                            _positioned(
                              comment.bounds,
                              widget.commentBuilder?.call(context, comment) ??
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xffb89b42,
                                      ).withValues(alpha: .14),
                                      border: Border.all(
                                        color: const Color(0xff9c894f),
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Text(
                                        comment.text,
                                        style: TextStyle(
                                          color: widget.theme.text,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                              key: ValueKey('comment:${comment.id}'),
                            ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: GraphConnectionPainter(
                                  current,
                                  camera,
                                  controller.selection,
                                  widget.theme,
                                  hovered: _hoveredEdge,
                                ),
                              ),
                            ),
                          ),
                        ),
                        for (final id in visible)
                          if (current.nodes[id] case final node?)
                            _positioned(
                              node.geometry.bounds,
                              Focus(
                                onFocusChange: (focused) {
                                  if (focused) {
                                    _focusedNodes.add(id);
                                  } else {
                                    _focusedNodes.remove(id);
                                  }
                                },
                                child: RepaintBoundary(
                                  child: _nodeContents(node),
                                ),
                              ),
                              key: ValueKey('node:$id'),
                            ),
                        for (final id in visible)
                          if (current.nodes[id] case final node?)
                            for (final port
                                in node.structure?.ports ?? <ResolvedPort>[])
                              _positioned(
                                GraphRect(
                                  node.geometry.ports[port.id]!.x - 7,
                                  node.geometry.ports[port.id]!.y - 7,
                                  14,
                                  14,
                                ),
                                IgnorePointer(
                                  child:
                                      widget.portBuilder?.call(
                                        context,
                                        node,
                                        port,
                                      ) ??
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color:
                                              port.kind == GraphPortKind.control
                                              ? widget.theme.node
                                              : widget.theme.data,
                                          border: Border.all(
                                            color:
                                                port.kind ==
                                                    GraphPortKind.control
                                                ? widget.theme.control
                                                : widget.theme.data,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                ),
                                key: ValueKey('port:$id:${port.id}'),
                              ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: GraphSelectionPainter(
                                current,
                                camera,
                                controller.selection,
                                widget.theme,
                                marquee: interaction is GraphMarquee
                                    ? GraphRect.fromPoints(
                                        interaction.origin,
                                        controller.camera.viewportToWorld(
                                          _pointer,
                                        ),
                                      )
                                    : null,
                                guides: _guides,
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: GraphExecutionPainter(
                                  current,
                                  camera,
                                  widget.executionSource,
                                  _animation,
                                  widget.theme,
                                  Listenable.merge([
                                    _animation,
                                    _executionRepaint,
                                  ]),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: GraphInteractionPainter(
                                camera,
                                widget.theme,
                                from: fixed,
                                to: fixed == null
                                    ? null
                                    : controller.camera.viewportToWorld(
                                        _pointer,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showMinimap)
              Positioned(
                right: 12,
                bottom: 12,
                child: GraphMinimap(
                  scene: current,
                  controller: controller,
                  viewport: _size,
                  theme: widget.theme,
                ),
              ),
            ...widget.overlays,
          ],
        );
      },
    ),
  );
}

class _GraphField extends StatefulWidget {
  const _GraphField({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
    required this.theme,
  });
  final ResolvedField field;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final GraphEditorTheme theme;
  @override
  State<_GraphField> createState() => _GraphFieldState();
}

class _GraphFieldState extends State<_GraphField> {
  late final TextEditingController text;
  final focus = FocusNode();
  String encode(Object? value) => value == null
      ? ''
      : value is String
      ? value
      : jsonEncode(value);
  @override
  void initState() {
    super.initState();
    text = TextEditingController(text: encode(widget.value));
  }

  @override
  void didUpdateWidget(_GraphField old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus && old.value != widget.value) {
      text.text = encode(widget.value);
    }
  }

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.field.kind == GraphFieldKind.boolean) {
      return Row(
        children: [
          Expanded(
            child: Text(
              widget.field.label,
              style: TextStyle(color: widget.theme.text, fontSize: 11),
            ),
          ),
          SizedBox(
            width: 40,
            child: Checkbox(
              value: widget.value == true,
              onChanged: (value) => widget.onChanged(value == true),
            ),
          ),
        ],
      );
    }
    final options = widget.field.metadata['options'];
    if (widget.field.kind == GraphFieldKind.choice && options is List) {
      final values = options.map((option) => '$option').toSet();
      return DropdownButton<String>(
        isExpanded: true,
        isDense: true,
        value: values.contains('${widget.value}') ? '${widget.value}' : null,
        hint: Text(widget.field.label),
        items: values
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
        onChanged: widget.onChanged,
      );
    }
    return TextField(
      controller: text,
      focusNode: focus,
      style: TextStyle(color: widget.theme.text, fontSize: 11),
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.field.label,
        labelStyle: TextStyle(
          color: widget.theme.text.withValues(alpha: .6),
          fontSize: 10,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        if (widget.field.kind == GraphFieldKind.number) {
          final number = num.tryParse(value);
          if (number != null && number.isFinite) widget.onChanged(number);
        } else if (widget.field.kind == GraphFieldKind.json) {
          try {
            widget.onChanged(jsonDecode(value));
          } on FormatException {
            /* Keep the local draft until it parses. */
          }
        } else {
          widget.onChanged(value);
        }
      },
    );
  }
}

class GraphMinimap extends StatefulWidget {
  const GraphMinimap({
    super.key,
    required this.scene,
    required this.controller,
    required this.viewport,
    required this.theme,
  });
  final GraphScene scene;
  final GraphController controller;
  final Size viewport;
  final GraphEditorTheme theme;
  @override
  State<GraphMinimap> createState() => _GraphMinimapState();
}

class _GraphMinimapState extends State<GraphMinimap> {
  bool collapsed = false;
  Size size = const Size(180, 110);
  GraphRect get bounds => widget.scene.bounds
      .union(graphViewport(widget.viewport, widget.controller.camera))
      .inflate(30);
  double get scale => math.min(
    size.width / math.max(1, bounds.width),
    size.height / math.max(1, bounds.height),
  );
  void recenter(Offset point) {
    final world = GraphPoint(
      bounds.left + point.dx / scale,
      bounds.top + point.dy / scale,
    );
    widget.controller.setCamera(
      GraphCamera(
        offset:
            GraphPoint(widget.viewport.width / 2, widget.viewport.height / 2) -
            world.scale(widget.controller.camera.zoom),
        zoom: widget.controller.camera.zoom,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
    color: widget.theme.node.withValues(alpha: .95),
    shape: RoundedRectangleBorder(
      side: BorderSide(color: widget.theme.border),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          height: 22,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(30, 20),
            ),
            onPressed: () => setState(() => collapsed = !collapsed),
            child: Text(
              collapsed ? 'Show minimap' : 'Hide minimap',
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
        if (!collapsed)
          Stack(
            children: [
              GestureDetector(
                onTapDown: (event) => recenter(event.localPosition),
                onPanUpdate: (event) => recenter(event.localPosition),
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: CustomPaint(
                    painter: _MinimapPainter(
                      widget.scene,
                      widget.controller.camera,
                      widget.controller.selection,
                      widget.viewport,
                      bounds,
                      scale,
                      widget.theme,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onPanUpdate: (event) => setState(
                    () => size = Size(
                      (size.width + event.delta.dx).clamp(100, 400),
                      (size.height + event.delta.dy).clamp(70, 300),
                    ),
                  ),
                  child: const Icon(Icons.drag_handle, size: 16),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter(
    this.scene,
    this.camera,
    this.selection,
    this.viewport,
    this.bounds,
    this.scale,
    this.theme,
  );
  final GraphScene scene;
  final GraphCamera camera;
  final GraphSelection selection;
  final Size viewport;
  final GraphRect bounds;
  final double scale;
  final GraphEditorTheme theme;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    canvas.translate(-bounds.left, -bounds.top);
    for (final frame in scene.space.frames.values) {
      canvas.drawRect(
        graphRect(frame.bounds),
        Paint()..color = theme.frame.withValues(alpha: .3),
      );
    }
    for (final edge in scene.connections.values) {
      canvas.drawPath(
        connectionPath(edge.geometry),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale
          ..color = theme.border,
      );
    }
    for (final node in scene.nodes.values) {
      canvas.drawRect(
        graphRect(node.geometry.bounds),
        Paint()
          ..color = selection.nodes.contains(node.node.id)
              ? theme.selected
              : Color(node.style.color),
      );
    }
    canvas.drawRect(
      graphRect(graphViewport(viewport, camera)),
      Paint()
        ..color = theme.text
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / scale,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MinimapPainter old) => true;
}
