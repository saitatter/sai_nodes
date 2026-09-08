import 'dart:async';

import 'package:sai_nodes/src/core/controller/core.dart';
import 'package:sai_nodes/src/core/events/events.dart';
import 'package:sai_nodes/src/core/localization/delegate.dart';
import 'package:sai_nodes/src/core/utils/rendering/renderbox.dart';
import 'package:sai_nodes/src/widgets/context_menu.dart';
import 'package:sai_nodes/src/widgets/improved_listener.dart';
import 'package:sai_nodes/src/widgets/node_editor_context_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';

import '../constants.dart';
import '../core/models/data.dart';
import 'builders.dart';

typedef _PortLocator = ({String nodeId, String portId});

/// The main NodeWidget which represents a node in the editor.
/// It now ensures that fields (regardless of whether a custom fieldBuilder is used)
/// still respond to tap events in the same way as before.
class DefaultNodeWidget extends StatefulWidget {
  final NodeEditorController controller;
  final NodeDataModel node;
  final NodeHeaderBuilder? headerBuilder;
  final NodeFieldBuilder? fieldBuilder;
  final NodePortBuilder? portBuilder;
  final NodeContextMenuBuilder? contextMenuBuilder;
  final NodeMenuBuilder? nodeMenuBuilder;
  final NodeBuilder? nodeBuilder;
  final NodeDoubleTapCallback? onNodeDoubleTap;
  final NodeResizeBuilder? resizeBuilder;

  const DefaultNodeWidget({
    super.key,
    required this.controller,
    required this.node,
    this.fieldBuilder,
    this.headerBuilder,
    this.portBuilder,
    this.contextMenuBuilder,
    this.nodeMenuBuilder,
    this.nodeBuilder,
    this.onNodeDoubleTap,
    this.resizeBuilder,
  });

  @override
  State<DefaultNodeWidget> createState() => _DefaultNodeWidgetState();
}

class _DefaultNodeWidgetState extends State<DefaultNodeWidget> {
  // Interaction state for linking ports.
  bool _isLinking = false;
  bool _resizePointer = false;

  // Timer for auto-scrolling when dragging near the edge.
  Timer? _edgeTimer;

  // The last known position of the pointer (GestureDetector).
  Offset? _lastPanPosition;

  // Temporary link locator used during linking.
  _PortLocator? _tempLink;

  // Desktop context menus are opened on pointer release. Opening the custom
  // node menu on pointer down lets the matching pointer up land on its
  // dismissible barrier and close it immediately.
  Offset? _pendingSecondaryMenuPosition;
  _PortLocator? _pendingSecondaryPort;

  late Color fakeTransparentColor;

  late List<PortDataModel> inPorts;
  late List<PortDataModel> outPorts;
  late List<FieldDataModel> fields;
  late final StreamSubscription<NodeEditorEvent> _eventSubscription;

  double get viewportZoom => widget.controller.viewportZoom;
  Offset get viewportOffset => widget.controller.viewportOffset;
  GlobalKey get editorKey => widget.controller.editorKey;

  @override
  void initState() {
    super.initState();

    _updateStyleCache();
    _updatePortsAndFields();

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _updatePortsPosition();
    });

    _eventSubscription = widget.controller.eventBus.events.listen(
      _handleControllerEvents,
    );
  }

  @override
  void dispose() {
    _edgeTimer?.cancel();
    _eventSubscription.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(DefaultNodeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.node.key != widget.node.key) {
      _updateStyleCache();
      _updatePortsAndFields();

      SchedulerBinding.instance.addPostFrameCallback((_) async {
        if (mounted) _updatePortsPosition();
      });
    }
  }

  void _handleControllerEvents(NodeEditorEvent event) {
    if (!mounted || event.isHandled) return;

    if (event is DragSelectionEvent) {
      if (!event.nodeIds.contains(widget.node.id)) return;

      SchedulerBinding.instance.addPostFrameCallback((_) async {
        if (mounted) _updatePortsPosition();
      });
    } else if (event is NodeLayoutEvent) {
      if (!event.nodeIds.contains(widget.node.id)) return;

      SchedulerBinding.instance.addPostFrameCallback((_) async {
        if (mounted) _updatePortsPosition();
      });
    } else if (event is NodeSelectionEvent) {
      if (event.nodeIds.contains(widget.node.id)) _updateStyleCache();
    } else if (event is NodeHoverEvent) {
      if (event.nodeId == widget.node.id) _updateStyleCache();
    } else if (event is CollapseNodeEvent) {
      if (!event.nodeIds.contains(widget.node.id)) return;

      _updateStyleCache();

      SchedulerBinding.instance.addPostFrameCallback((_) async {
        if (mounted) _updatePortsPosition();
      });
    } else if (event is NodeFieldEvent) {
      if (event.nodeId == widget.node.id &&
          (event.eventType == FieldEventType.submit ||
              event.eventType == FieldEventType.cancel)) {
        setState(() {});
      }
    } else if (event is NodeRenameEvent) {
      if (event.nodeId != widget.node.id) return;
      setState(() {});
    } else if (event is NodeResizeEvent) {
      if (event.nodeId != widget.node.id) return;
      setState(() {});
      {
        SchedulerBinding.instance.addPostFrameCallback((_) async {
          if (mounted) _updatePortsPosition();
        });
      }
    } else if (event is AddNodeEvent) {
      if (event.node.id == widget.node.id) setState(() {});
    } else if (event is ConfigurationChangeEvent ||
        event is StyleChangeEvent ||
        event is LocaleChangeEvent) {
      _updatePortsAndFields();
      _updateStyleCache();

      SchedulerBinding.instance.addPostFrameCallback((_) async {
        if (mounted) _updatePortsPosition();
      });
    }
  }

  void _startEdgeTimer(Offset position) {
    const edgeThreshold = 50.0;
    final moveAmount = 5.0 / widget.controller.viewportZoom;
    final editorBounds = RenderBoxUtils.getEditorBoundsInScreen(editorKey);
    if (editorBounds == null) return;

    _edgeTimer?.cancel();

    _edgeTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      double dx = 0;
      double dy = 0;
      final rect = editorBounds;

      if (position.dx < rect.left + edgeThreshold) {
        dx = -moveAmount;
      } else if (position.dx > rect.right - edgeThreshold) {
        dx = moveAmount;
      }
      if (position.dy < rect.top + edgeThreshold) {
        dy = -moveAmount;
      } else if (position.dy > rect.bottom - edgeThreshold) {
        dy = moveAmount;
      }

      if (dx != 0 || dy != 0) {
        widget.controller.dragSelection(Offset(dx, dy));
        widget.controller.setViewportOffset(
          Offset(-dx / viewportZoom, -dy / viewportZoom),
          animate: false,
        );
      }
    });
  }

  void _resetEdgeTimer() {
    _edgeTimer?.cancel();
  }

  _PortLocator? _isNearPort(Offset position) {
    final worldPosition = RenderBoxUtils.screenToWorld(
      editorKey,
      position,
      viewportOffset,
      viewportZoom,
    );

    final near = Rect.fromCenter(
      center: worldPosition!,
      width: kSpatialHashingCellSize,
      height: kSpatialHashingCellSize,
    );

    final nearNodeIds = widget.controller.nodesSpatialHashGrid.queryArea(near);

    for (final nodeId in nearNodeIds) {
      final node = widget.controller.getNodeById(nodeId)!;
      for (final port in node.ports.values) {
        final absolutePortPosition = node.offset + port.offset;
        if ((worldPosition - absolutePortPosition).distance <=
            widget.controller.config.portHitTestTolerance) {
          return (nodeId: node.id, portId: port.prototype.idName);
        }
      }
    }

    return null;
  }

  void _onTmpLinkStart(_PortLocator locator) {
    _tempLink = (nodeId: locator.nodeId, portId: locator.portId);
    _isLinking = true;
  }

  void _onTmpLinkUpdate(Offset position) {
    final worldPosition = RenderBoxUtils.screenToWorld(
      editorKey,
      position,
      viewportOffset,
      viewportZoom,
    );
    final node = widget.controller.getNodeById(_tempLink!.nodeId)!;
    final port = node.ports[_tempLink!.portId]!;
    final absolutePortOffset = node.offset + port.offset;

    widget.controller.drawTempLink(
      port.style.linkStyleBuilder(LinkState()),
      absolutePortOffset,
      worldPosition!,
    );
  }

  void _onTmpLinkCancel() {
    _isLinking = false;
    _tempLink = null;
    widget.controller.clearTempLink();
  }

  void _onTmpLinkEnd(_PortLocator locator) {
    widget.controller.addLink(
      _tempLink!.nodeId,
      _tempLink!.portId,
      locator.nodeId,
      locator.portId,
    );
    _isLinking = false;
    _tempLink = null;
    widget.controller.clearTempLink();
  }

  Widget controlsWrapper(Widget child) {
    final platform = Theme.of(context).platform;
    final isMobilePlatform =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;

    final wrappedChild = isMobilePlatform
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (!widget.node.state.isSelected) {
                widget.controller.selectNodesById({widget.node.id});
              }
            },
            onLongPressStart: (details) {
              final position = details.globalPosition;
              final locator = _isNearPort(position);

              if (!widget.node.state.isSelected) {
                widget.controller.selectNodesById({widget.node.id});
              }

              if (locator != null && !widget.node.state.isCollapsed) {
                createAndShowContextMenu(
                  context,
                  entries: _portContextMenuEntries(position, locator: locator),
                  position: position,
                );
              } else {
                widget.controller.selectNodesById({widget.node.id});
                _showNodeContextMenu(position);
              }
            },
            onPanDown: (details) {
              _lastPanPosition = details.globalPosition;
            },
            onPanStart: (details) {
              final position = details.globalPosition;
              _isLinking = false;
              _tempLink = null;

              final locator = _isNearPort(position);
              if (locator != null) {
                _isLinking = true;
                _onTmpLinkStart(locator);
              } else {
                if (!widget.node.state.isSelected) {
                  widget.controller.selectNodesById({widget.node.id});
                }
              }
            },
            onPanUpdate: (details) {
              _lastPanPosition = details.globalPosition;
              if (_isLinking) {
                _onTmpLinkUpdate(details.globalPosition);
              } else {
                _startEdgeTimer(details.globalPosition);
                widget.controller.dragSelection(details.delta);
              }
            },
            onPanEnd: (details) {
              if (_isLinking) {
                final locator = _isNearPort(_lastPanPosition!);
                if (locator != null) {
                  _onTmpLinkEnd(locator);
                } else {
                  createAndShowContextMenu(
                    context,
                    entries: _createSubmenuEntries(_lastPanPosition!),
                    position: _lastPanPosition!,
                    onDismiss: (value) => _onTmpLinkCancel(),
                  );
                }
                _isLinking = false;
              } else {
                _resetEdgeTimer();
              }
            },
            child: child,
          )
        : ImprovedListener(
            behavior: HitTestBehavior.translucent,
            onPointerPressed: (event) async {
              if (_resizePointer) return;
              _isLinking = false;
              _tempLink = null;

              final locator = _isNearPort(event.position);
              if (event.buttons & kSecondaryMouseButton != 0) {
                if (!widget.node.state.isSelected) {
                  widget.controller.selectNodesById({widget.node.id});
                }

                _pendingSecondaryMenuPosition = event.position;
                _pendingSecondaryPort =
                    locator != null && !widget.node.state.isCollapsed
                        ? locator
                        : null;
              } else if (event.buttons == kPrimaryMouseButton) {
                if (locator != null && !_isLinking && _tempLink == null) {
                  _onTmpLinkStart(locator);
                } else if (!widget.node.state.isSelected) {
                  widget.controller.selectNodesById(
                    {widget.node.id},
                    holdSelection: HardwareKeyboard.instance.isControlPressed,
                  );
                }
              }
            },
            onPointerMoved: (event) async {
              if (_resizePointer) return;
              if (_isLinking) {
                _onTmpLinkUpdate(event.position);
              } else if (event.buttons == kPrimaryMouseButton) {
                _startEdgeTimer(event.position);
                widget.controller.dragSelection(event.delta);
              }
            },
            onPointerReleased: (event) async {
              if (_resizePointer) {
                _resizePointer = false;
                return;
              }
              final pendingPosition = _pendingSecondaryMenuPosition;
              if (pendingPosition != null) {
                final pendingPort = _pendingSecondaryPort;
                _pendingSecondaryMenuPosition = null;
                _pendingSecondaryPort = null;
                if (pendingPort != null) {
                  createAndShowContextMenu(
                    context,
                    entries: _portContextMenuEntries(
                      event.position,
                      locator: pendingPort,
                    ),
                    position: event.position,
                  );
                } else {
                  _showNodeContextMenu(event.position);
                }
              } else if (_isLinking) {
                final locator = _isNearPort(event.position);
                if (locator != null) {
                  _onTmpLinkEnd(locator);
                } else {
                  createAndShowContextMenu(
                    context,
                    entries: _createSubmenuEntries(event.position),
                    position: event.position,
                    onDismiss: (value) => _onTmpLinkCancel(),
                  );
                }
              } else {
                _resetEdgeTimer();
              }
            },
            onPointerCanceled: (_) {
              _pendingSecondaryMenuPosition = null;
              _pendingSecondaryPort = null;
              _resetEdgeTimer();
            },
            child: child,
          );

    if (widget.onNodeDoubleTap == null) return wrappedChild;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () => widget.onNodeDoubleTap!(context, widget.node),
      child: wrappedChild,
    );
  }

  List<ContextMenuEntry> _defaultNodeContextMenuEntries() {
    final strings = NodeEditorLocalizations.of(context);

    return [
      MenuHeader(text: strings.nodeMenuLabel),
      MenuItem<dynamic>(
        label: Text(strings.seeNodeDescriptionAction),
        icon: const Icon(Icons.info),
        onSelected: (_) {
          showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: Text(widget.node.prototype.displayName(context)),
                content: Text(widget.node.prototype.description(context)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.closeAction),
                  ),
                ],
              );
            },
          );
        },
      ),
      const MenuDivider(),
      MenuItem<dynamic>(
        label: Text(
          widget.node.state.isCollapsed
              ? strings.expandNodeAction
              : strings.collapseNodeAction,
        ),
        icon: Icon(
          widget.node.state.isCollapsed
              ? Icons.arrow_drop_down
              : Icons.arrow_right,
        ),
        onSelected: (_) => widget.controller
            .toggleCollapseSelectedNodes(!widget.node.state.isCollapsed),
      ),
      const MenuDivider(),
      MenuItem<dynamic>(
        label: Text(strings.deleteNodeAction),
        icon: const Icon(Icons.delete),
        onSelected: (_) {
          if (widget.node.state.isSelected) {
            widget.controller.deleteSelection();
          } else {
            widget.controller.removeNodeById(widget.node.id);
            widget.controller.clearSelection();
          }
        },
      ),
      MenuItem<dynamic>(
        label: Text(strings.cutSelectionAction),
        icon: const Icon(Icons.content_cut),
        onSelected: (_) =>
            widget.controller.clipboard.cutSelection(context: context),
      ),
      MenuItem<dynamic>(
        label: Text(strings.copySelectionAction),
        icon: const Icon(Icons.copy),
        onSelected: (_) =>
            widget.controller.clipboard.copySelection(context: context),
      ),
    ];
  }

  void _showNodeContextMenu(Offset position) {
    final menuBuilder = widget.nodeMenuBuilder;
    if (menuBuilder != null) {
      showNodeEditorContextMenu(
        context,
        position: position,
        entries: menuBuilder(context, widget.node),
      );
    } else if (!isContextMenuVisible) {
      final entries = widget.contextMenuBuilder != null
          ? widget.contextMenuBuilder!(context, widget.node)
          : _defaultNodeContextMenuEntries();
      createAndShowContextMenu(
        context,
        entries: entries,
        position: position,
      );
    }
  }

  List<ContextMenuEntry> _portContextMenuEntries(
    Offset position, {
    required _PortLocator locator,
  }) {
    final strings = NodeEditorLocalizations.of(context);

    return [
      MenuHeader(text: strings.portMenuLabel),
      MenuItem<dynamic>(
        label: Text(strings.cutLinksAction),
        icon: const Icon(Icons.remove_circle),
        onSelected: (_) {
          widget.controller.breakPortLinks(locator.nodeId, locator.portId);
        },
      ),
    ];
  }

  List<ContextMenuEntry> _createSubmenuEntries(Offset position) {
    final fromLink = _tempLink != null;
    final List<MapEntry<String, NodePrototype>> compatiblePrototypes = [];

    if (fromLink) {
      final startPort = widget.controller
          .getNodeById(_tempLink!.nodeId)!
          .ports[_tempLink!.portId]!;
      widget.controller.nodePrototypes.forEach((key, value) {
        if (value.ports.any(
          startPort.prototype.compatibleWith,
        )) {
          compatiblePrototypes.add(MapEntry(key, value));
        }
      });
    } else {
      widget.controller.nodePrototypes.forEach(
        (key, value) => compatiblePrototypes.add(MapEntry(key, value)),
      );
    }

    final worldPosition = RenderBoxUtils.screenToWorld(
      editorKey,
      position,
      viewportOffset,
      viewportZoom,
    );

    return compatiblePrototypes.map((entry) {
      return MenuItem<dynamic>(
        label: Text(entry.value.displayName(context)),
        icon: const Icon(Icons.widgets),
        onSelected: (_) {
          final addedNode = widget.controller.addNode(
            entry.key,
            offset: worldPosition ?? Offset.zero,
          );
          if (fromLink) {
            final startPort = widget
                .controller.nodes[_tempLink!.nodeId]!.ports[_tempLink!.portId]!;

            widget.controller.addLink(
              _tempLink!.nodeId,
              _tempLink!.portId,
              addedNode.id,
              addedNode.ports.values
                  .map((port) => port.prototype)
                  .firstWhere(
                    startPort.prototype.compatibleWith,
                  )
                  .idName,
            );

            _isLinking = false;
            _tempLink = null;
          }
        },
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // If a custom nodeBuilder is provided, use it directly.
    if (widget.nodeBuilder != null) {
      return widget.nodeBuilder!(context, widget.node);
    }

    final nodeContent = Stack(
      key: widget.node.key,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: widget.node.builtStyle.decoration,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            widget.headerBuilder != null
                ? widget.headerBuilder!(
                    context,
                    widget.node,
                    widget.node.builtStyle,
                    () => widget.controller.toggleCollapseSelectedNodes(
                      !widget.node.state.isCollapsed,
                    ),
                  )
                : _NodeHeaderWidget(
                    controller: widget.controller,
                    node: widget.node,
                  ),
            Offstage(
              offstage: widget.node.state.isCollapsed,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: inPorts
                                .map(
                                  (port) => _PortWidget(
                                    node: widget.node,
                                    port: port,
                                    portBuilder: widget.portBuilder,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: outPorts
                                .map(
                                  (port) => _PortWidget(
                                    node: widget.node,
                                    port: port,
                                    portBuilder: widget.portBuilder,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                    if (fields.isNotEmpty) const SizedBox(height: 16),
                    ...fields.map(
                      (field) => _FieldWidget(
                        controller: widget.controller,
                        node: widget.node,
                        field: field,
                        fieldBuilder: widget.fieldBuilder,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (widget.resizeBuilder != null)
          Positioned(
            right: 4,
            bottom: 4,
            child: Listener(
              onPointerDown: (_) => _resizePointer = true,
              onPointerCancel: (_) => _resizePointer = false,
              child: widget.resizeBuilder!(
                context,
                widget.node,
                (size) => widget.controller.resizeNode(
                  widget.node.id,
                  size,
                ),
              ),
            ),
          ),
        if (widget.resizeBuilder == null &&
            widget.controller.config.enableNodeResize)
          Positioned(
            right: 2,
            bottom: 2,
            child: Listener(
              onPointerDown: (_) => _resizePointer = true,
              onPointerCancel: (_) => _resizePointer = false,
              child: _DefaultNodeResizeHandle(
                node: widget.node,
                onResize: (size) => widget.controller.resizeNode(
                  widget.node.id,
                  size,
                ),
              ),
            ),
          ),
      ],
    );

    final fixedSize = widget.node.customSize;
    final sizedNode = fixedSize == null
        ? IntrinsicHeight(
            child: IntrinsicWidth(child: nodeContent),
          )
        : SizedBox(
            width: fixedSize.width,
            height: fixedSize.height,
            child: nodeContent,
          );

    return controlsWrapper(sizedNode);
  }

  void _updateStyleCache() {
    setState(() {
      widget.node.builtStyle =
          widget.node.prototype.styleBuilder(widget.node.state);
      widget.node.builtHeaderStyle =
          widget.node.prototype.headerStyleBuilder(widget.node.state);

      fakeTransparentColor = Color.alphaBlend(
        widget.node.builtStyle.decoration.color!.withAlpha(255),
        widget.node.builtStyle.decoration.color!,
      );
    });
  }

  void _updatePortsAndFields() {
    setState(() {
      inPorts = widget.node.ports.values
          .where((port) => port.prototype.direction == PortDirection.input)
          .toList();
      outPorts = widget.node.ports.values
          .where((port) => port.prototype.direction == PortDirection.output)
          .toList();

      fields = widget.node.fields.values.toList();
    });
  }

  void _updatePortsPosition() {
    // Early return with combined null checks
    final renderBox = context.findRenderObject() as RenderBox?;
    final nodeBox =
        widget.node.key.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox == null || nodeBox == null) return;

    // Cache frequently used values
    final renderBoxSize = renderBox.size;
    final isCollapsed = widget.node.state.isCollapsed;
    final collapsedYAdjustment = isCollapsed ? -renderBoxSize.height + 8 : 0;

    // Process ports
    for (final port in widget.node.ports.values) {
      final portBox = port.key.currentContext?.findRenderObject() as RenderBox?;
      if (portBox == null) continue;

      // Calculate relative offset with collapsed adjustment
      final portOffset = portBox.localToGlobal(Offset.zero, ancestor: nodeBox);
      final relativeY = portOffset.dy + collapsedYAdjustment;

      // Set port offset based on direction
      port.offset = Offset(
        port.prototype.direction == PortDirection.input
            ? 0
            : renderBoxSize.width,
        relativeY + portBox.size.height / 2,
      );
    }
  }
}

class _DefaultNodeResizeHandle extends StatefulWidget {
  const _DefaultNodeResizeHandle({
    required this.node,
    required this.onResize,
  });

  final NodeDataModel node;
  final void Function(Size size) onResize;

  @override
  State<_DefaultNodeResizeHandle> createState() =>
      _DefaultNodeResizeHandleState();
}

class _DefaultNodeResizeHandleState extends State<_DefaultNodeResizeHandle> {
  Size? _size;

  void _startResize() {
    final renderBox = widget.node.key.currentContext?.findRenderObject();
    final renderedSize = renderBox is RenderBox ? renderBox.size : null;
    final size = widget.node.customSize ?? renderedSize;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    _size = size;
  }

  void _updateResize(DragUpdateDetails details) {
    final size = _size;
    if (size == null) return;
    _size = Size(
      size.width + details.delta.dx,
      size.height + details.delta.dy,
    );
    widget.onResize(_size!);
  }

  void _endResize() => _size = null;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeDownRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _startResize(),
        onPanUpdate: _updateResize,
        onPanEnd: (_) => _endResize(),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: Icon(Icons.open_in_full, size: 13),
        ),
      ),
    );
  }
}

class _NodeHeaderWidget extends StatelessWidget {
  final NodeEditorController controller;
  final NodeDataModel node;

  const _NodeHeaderWidget({
    required this.controller,
    required this.node,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: node.builtHeaderStyle.padding,
      decoration: node.builtHeaderStyle.decoration,
      child: Row(
        children: [
          InkWell(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashFactory: NoSplash.splashFactory,
            onTap: () => controller.toggleCollapseSelectedNodes(
              !node.state.isCollapsed,
            ),
            child: Icon(
              node.builtHeaderStyle.icon,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              node.displayTitle(context),
              style: node.builtHeaderStyle.textStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PortWidget extends StatelessWidget {
  final NodeDataModel node;
  final PortDataModel port;
  final NodePortBuilder? portBuilder;

  const _PortWidget({
    required this.node,
    required this.port,
    this.portBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (node.state.isCollapsed) {
      return SizedBox(key: port.key, height: 0, width: 0);
    }

    if (portBuilder != null) {
      return portBuilder!(context, port, node.builtStyle);
    }

    final isInput = port.prototype.direction == PortDirection.input;

    return Row(
      mainAxisAlignment:
          isInput ? MainAxisAlignment.start : MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      key: port.key,
      children: [
        Flexible(
          child: Text(
            port.prototype.displayName(context),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            overflow: TextOverflow.ellipsis,
            textAlign: isInput ? TextAlign.left : TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _FieldWidget extends StatelessWidget {
  final NodeEditorController controller;
  final NodeDataModel node;
  final FieldDataModel field;
  final NodeFieldBuilder? fieldBuilder;

  const _FieldWidget({
    required this.controller,
    required this.node,
    required this.field,
    this.fieldBuilder,
  });

  void _showFieldEditorOverlay(
    BuildContext context,
    TapDownDetails details,
  ) {
    final overlay = Overlay.of(context);
    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            GestureDetector(
              onTap: () => overlayEntry?.remove(),
              child: Container(color: Colors.transparent),
            ),
            Positioned(
              left: details.globalPosition.dx,
              top: details.globalPosition.dy,
              child: Material(
                child: field.prototype.editorBuilder!(
                  context,
                  () => overlayEntry?.remove(),
                  field.data,
                  (dynamic data, {required FieldEventType eventType}) {
                    controller.setFieldData(
                      node.id,
                      field.prototype.idName,
                      data: data,
                      eventType: eventType,
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(overlayEntry);
  }

  @override
  Widget build(BuildContext context) {
    if (node.state.isCollapsed) {
      return SizedBox.shrink(key: field.key);
    }

    // Get the field content either from the custom builder or use default visualizer.
    final fieldContent = fieldBuilder != null
        ? fieldBuilder!(context, field, node.builtStyle)
        : Container(
            padding: field.prototype.style.padding,
            decoration: field.prototype.style.decoration,
            child: Row(
              spacing: 8,
              children: [
                Flexible(
                  child: Text(
                    field.prototype.displayName(context),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: field.prototype.visualizerBuilder(field.data),
                ),
              ],
            ),
          );

    // Wrap the content with a GestureDetector to ensure tap handling.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTapDown: (details) {
          if (field.prototype.onVisualizerTap != null) {
            field.prototype.onVisualizerTap!(field.data, (dynamic data) {
              controller.setFieldData(
                node.id,
                field.prototype.idName,
                data: data,
                eventType: FieldEventType.submit,
              );
            });
          } else {
            _showFieldEditorOverlay(context, details);
          }
        },
        child: fieldContent,
      ),
    );
  }
}
