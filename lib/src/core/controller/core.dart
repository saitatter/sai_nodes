import 'dart:async';
import 'dart:math';

import 'package:sai_nodes/src/core/controller/callback.dart';
import 'package:sai_nodes/src/core/controller/content_revision.dart';
import 'package:sai_nodes/src/core/controller/history.dart';
import 'package:sai_nodes/src/core/controller/navigation.dart';
import 'package:sai_nodes/src/core/controller/project.dart';
import 'package:sai_nodes/src/core/controller/viewport_transform.dart';
import 'package:sai_nodes/src/core/events/events.dart';
import 'package:sai_nodes/src/core/utils/dsa/spatial_hash_grid.dart';
import 'package:sai_nodes/src/core/utils/rendering/renderbox.dart';
import 'package:flutter/foundation.dart';
import 'package:sai_nodes/src/styles/styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:uuid/uuid.dart';

import '../events/bus.dart';
import '../models/data.dart';
import 'clipboard.dart';
import 'config.dart';
import 'runner.dart';
import 'utils.dart';

export 'config.dart';

/// A controller class for the Node Editor.
///
/// This class is responsible for managing the state of the node editor,
/// including the nodes, links, and the viewport. It also provides methods
/// for adding, removing, and manipulating nodes and links.
///
/// The controller also provides an event bus for the node editor, allowing
/// different parts of the application to communicate with each other by
/// sending and receiving events.
class NodeEditorController with ChangeNotifier {
  Callback? onCallback;
  final NodeEditorClipboardPayloadEncoder? clipboardPayloadEncoder;
  final NodeEditorClipboardPayloadDecoder? clipboardPayloadDecoder;
  GlobalKey editorKey;

  NodeEditorController({
    this.config = const NodeEditorConfig(),
    this.style = const NodeEditorStyle(),
    ProjectSaver? projectSaver,
    ProjectLoader? projectLoader,
    ProjectCreator? projectCreator,
    this.onCallback,
    this.clipboardPayloadEncoder,
    this.clipboardPayloadDecoder,
    GlobalKey? editorKey,
  }) : editorKey = editorKey ?? GlobalKey() {
    clipboard = NodeEditorClipboardHelper(
      this,
      payloadEncoder: clipboardPayloadEncoder,
      payloadDecoder: clipboardPayloadDecoder,
    );
    runner = NodeEditorExecutionHelper(this);
    history = NodeEditorHistoryHelper(this);
    project = NodeEditorProjectHelper(
      this,
      projectSaver: projectSaver,
      projectLoader: projectLoader,
      projectCreator: projectCreator,
    );
    _stateEventSubscription = eventBus.events.listen(_handleStateEvent);
  }

  void _handleStateEvent(NodeEditorEvent event) {
    notifyListeners();
    if (isNodeEditorContentMutation(event)) {
      contentRevisionNotifier.value++;
    }
  }

  /// This method is used to dispose of the node editor controller and all of its resources, subsystems and members.
  @override
  void dispose() {
    _stateEventSubscription.cancel();
    if (_hasTickerProvider) {
      _viewportOffsetAnimController.dispose();
      _viewportZoomAnimController.dispose();
      _hasTickerProvider = false;
    }
    history.dispose();
    project.dispose();
    eventBus.close();
    runner.clear();

    clear();
    viewportOffsetNotifier.dispose();
    viewportZoomNotifier.dispose();
    contentRevisionNotifier.dispose();

    super.dispose();
  }

  /// This method is used to clear the core controller and all of its subsystems.
  void clear() {
    nodes.clear();
    links.clear();
    nodesSpatialHashGrid.clear();
    selectedNodeIds.clear();
    selectedLinkIds.clear();

    unboundNodeOffsets.clear();
    _highlightArea = null;
    _tempLink = null;

    linksDataDirty = true;
    nodesDataDirty = true;
  }

  ////////////////////////////////////////////////////////////////////////////////
  /// Controller subsystems are used to manage the state of the node editor.
  ////////////////////////////////////////////////////////////////////////////////

  /// The event bus communicates between controller subsystems and the UI.
  final eventBus = NodeEditorEventBus();
  late final StreamSubscription<NodeEditorEvent> _stateEventSubscription;

  late final NodeEditorClipboardHelper clipboard;
  late final NodeEditorExecutionHelper runner;
  late final NodeEditorHistoryHelper history;
  late final NodeEditorProjectHelper project;

  ////////////////////////////////////////////////////////////////////////////////
  /// Animation properties are used to manage animations in the node editor.
  ////////////////////////////////////////////////////////////////////////////////

  TickerProvider? _tickerProvider;

  late AnimationController _viewportOffsetAnimController;
  late AnimationController _viewportZoomAnimController;
  late Animation<Offset> _viewportOffsetAnim;
  late Animation<double> _viewportZoomAnim;
  bool _hasTickerProvider = false;

  void setTickerProvider(TickerProvider tickerProvider) {
    if (_hasTickerProvider) {
      _viewportOffsetAnimController.dispose();
      _viewportZoomAnimController.dispose();
    }

    _tickerProvider = tickerProvider;

    _viewportOffsetAnimController = AnimationController(
      vsync: _tickerProvider!,
    );
    _viewportZoomAnimController = AnimationController(
      vsync: _tickerProvider!,
    );
    _hasTickerProvider = true;
  }

  ////////////////////////////////////////////////////////////////////////////////
  /// Viewport properties are used to manage the viewport of the node editor.
  ////////////////////////////////////////////////////////////////////////////////

  final ValueNotifier<Offset> viewportOffsetNotifier =
      ValueNotifier(Offset.zero);
  final ValueNotifier<double> viewportZoomNotifier = ValueNotifier(1.0);

  /// Increases whenever an event changes persisted node-editor content.
  final ValueNotifier<int> contentRevisionNotifier = ValueNotifier(0);

  ValueListenable<int> get contentRevision => contentRevisionNotifier;

  Offset get viewportOffset => viewportOffsetNotifier.value;
  double get viewportZoom => viewportZoomNotifier.value;

  /// Returns the coordinate transform for the current viewport state.
  NodeEditorViewportTransform viewportTransform(Size viewportSize) =>
      NodeEditorViewportTransform(
        viewportSize: viewportSize,
        viewportOffset: viewportOffset,
        zoom: viewportZoom,
      );

  /// Converts a local editor-screen position into world coordinates.
  Offset screenToWorld(Offset screenPosition, Size viewportSize) =>
      viewportTransform(viewportSize).screenToWorld(screenPosition);

  /// Converts a world position into local editor-screen coordinates.
  Offset worldToScreen(Offset worldPosition, Size viewportSize) =>
      viewportTransform(viewportSize).worldToScreen(worldPosition);

  /// Returns the world rectangle currently visible in an editor viewport.
  Rect visibleWorldBounds(Size viewportSize) =>
      viewportTransform(viewportSize).visibleWorldBounds;

  /// This method is used to set the offset of the viewport.
  ///
  /// The 'animate' parameter is used to animate the transition to the new offset.
  /// The 'absolute' parameter is used to choose whether the offset is added to the the current
  /// offset or set as an absolute value. The 'isHandled' parameter is used to indicate whether
  void setViewportOffset(
    Offset offset, {
    bool animate = true,
    bool absolute = false,
    bool isHandled = false,
  }) {
    if (viewportOffset == offset) return;

    _viewportOffsetAnimController.stop();

    final beginOffset = viewportOffset;

    final tempOffset = absolute ? offset : offset + beginOffset;

    final Offset endOffset = Offset(
      tempOffset.dx.clamp(
        -config.maxPanX,
        config.maxPanX,
      ),
      tempOffset.dy.clamp(
        -config.maxPanY,
        config.maxPanY,
      ),
    );

    if (animate) {
      _viewportOffsetAnimController.reset();

      final distance = (offset - endOffset).distance;
      final durationFactor = (distance / 1000).clamp(0.5, 3.0);

      _viewportOffsetAnimController.duration = Duration(
        milliseconds: (1000 * durationFactor).toInt(),
      );

      _viewportOffsetAnim = Tween<Offset>(
        begin: beginOffset,
        end: endOffset,
      ).animate(
        CurvedAnimation(
          parent: _viewportOffsetAnimController,
          curve: Curves.easeOut,
        ),
      )..addListener(() {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            viewportOffsetNotifier.value = _viewportOffsetAnim.value;

            eventBus.emit(
              ViewportOffsetEvent(
                id: const Uuid().v4(),
                _viewportOffsetAnim.value,
                animate: animate,
                isHandled: isHandled,
              ),
            );
          });
        });

      _viewportOffsetAnimController.forward();
    } else {
      viewportOffsetNotifier.value = endOffset;

      eventBus.emit(
        ViewportOffsetEvent(
          id: const Uuid().v4(),
          endOffset,
          animate: animate,
          isHandled: isHandled,
        ),
      );
    }
  }

  /// This method is used to set the zoom level of the viewport.
  ///
  /// The 'animate' parameter is used to animate the zoom transition.
  ///
  /// NOTE: The focal point defaults to the current viewport offset if not provided and uses cursor position from mouse events.
  void setViewportZoom(
    double zoom, {
    bool animate = true,
    bool absolute = false,
    bool isHandled = false,
  }) {
    if (viewportZoom == zoom) return;

    _viewportZoomAnimController.stop();

    final beginZoom = viewportZoom;

    final endZoom = (absolute ? zoom : viewportZoom + zoom).clamp(
      config.minZoom,
      config.maxZoom,
    );

    if (animate) {
      _viewportZoomAnimController.reset();

      _viewportZoomAnimController.duration = const Duration(milliseconds: 200);

      _viewportZoomAnim = Tween<double>(
        begin: beginZoom,
        end: endZoom,
      ).animate(
        CurvedAnimation(
          parent: _viewportZoomAnimController,
          curve: Curves.easeOut,
        ),
      )..addListener(() {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            lodLevelNotifier.value = _computeLODLevel(viewportZoom);
            viewportZoomNotifier.value = _viewportZoomAnim.value;

            eventBus.emit(
              ViewportZoomEvent(
                id: const Uuid().v4(),
                _viewportZoomAnim.value,
                animate: animate,
                isHandled: isHandled,
              ),
            );
          });
        });

      _viewportZoomAnimController.forward();
    } else {
      lodLevelNotifier.value = _computeLODLevel(endZoom);
      viewportZoomNotifier.value = endZoom;

      eventBus.emit(
        ViewportZoomEvent(
          id: const Uuid().v4(),
          endZoom,
          animate: animate,
          isHandled: isHandled,
        ),
      );
    }
  }

  ////////////////////////////////////////////////////////////////////////////////
  /// Rendering accelerators are data stored in the controller to speed up rendering.
  ////////////////////////////////////////////////////////////////////////////////

  late final lodLevelNotifier =
      ValueNotifier<int>(_computeLODLevel(viewportZoom));
  int get lodLevel => lodLevelNotifier.value;

  bool nodesDataDirty = false;
  bool linksDataDirty = false;

  /// This method is used to compute the level of detail (LOD) based on the zoom level and
  /// it's called automatically by the controller when the zoom level is changed.
  static int _computeLODLevel(double zoom) {
    if (zoom > 0.5) {
      return 4;
    } else if (zoom > 0.25) {
      return 3;
    } else if (zoom > 0.125) {
      return 2;
    } else if (zoom > 0.0625) {
      return 1;
    } else {
      return 0;
    }
  }

  ////////////////////////////////////////////////////////////////////////////////
  /// Node editor configuration and style.
  //////////////////////////////////////////////////////////////////////////////////

  NodeEditorConfig config;

  /// Set the global configuration of the node editor.
  void setConfig(NodeEditorConfig config) {
    if (config == this.config) return;

    this.config = config;

    nodesDataDirty = true;
    linksDataDirty = true;

    eventBus.emit(
      ConfigurationChangeEvent(
        config,
        id: const Uuid().v4(),
      ),
    );
  }

  /// Returns the effective minimum size for [node], including any host
  /// calculation required to keep visible ports and fields readable.
  Size minimumNodeSizeFor(NodeDataModel node) {
    final calculated = config.minimumNodeSizeBuilder?.call(
      inputPortCount: node.ports.values
          .where((port) => port.prototype.direction == PortDirection.input)
          .length,
      outputPortCount: node.ports.values
          .where((port) => port.prototype.direction == PortDirection.output)
          .length,
      fieldCount: node.fields.length,
    );
    final minimum =
        calculated ?? Size(config.minNodeWidth, config.minNodeHeight);
    return Size(
      minimum.width.clamp(config.minNodeWidth, config.maxNodeWidth).toDouble(),
      minimum.height
          .clamp(config.minNodeHeight, config.maxNodeHeight)
          .toDouble(),
    );
  }

  /// Quick access to frequently used configuration properties.

  /// Enable or disable snapping nodes to the configured grid.
  void enableSnapToGrid(bool enable) async {
    if (!enable) {
      for (final node in nodes.values) {
        node.offset = unboundNodeOffsets[node.id] ?? node.offset;
      }
    } else {
      for (final node in nodes.values) {
        node.offset = Offset(
          (node.offset.dx / config.snapToGridSize).round() *
              config.snapToGridSize,
          (node.offset.dy / config.snapToGridSize).round() *
              config.snapToGridSize,
        );
      }
    }

    setConfig(config.copyWith(enableSnapToGrid: enable));
  }

  /// Set the size of the grid to snap to in the node editor.
  void setSnapToGridSize(double size) =>
      setConfig(config.copyWith(snapToGridSize: size));

  /// Enable or disable auto placement of nodes in the node editor.
  void enableAutoPlacement(bool enable) =>
      setConfig(config.copyWith(enableAutoPlacement: enable));

  NodeEditorStyle style;

  /// Set the style of the node editor.
  void setStyle(NodeEditorStyle style) {
    if (style == this.style) return;

    this.style = style;

    nodesDataDirty = true;
    linksDataDirty = true;

    eventBus.emit(
      StyleChangeEvent(
        style,
        id: const Uuid().v4(),
      ),
    );
  }

  ////////////////////////////////////////////////////////////////////////
  /// Localization.
  ////////////////////////////////////////////////////////////////////////

  Locale locale = const Locale('en');

  /// Set the locale of the node editor.
  void setLocale(Locale locale) {
    if (locale == this.locale) return;

    this.locale = locale;

    nodesDataDirty = true;
    linksDataDirty = true;

    eventBus.emit(
      LocaleChangeEvent(
        locale,
        id: const Uuid().v4(),
      ),
    );
  }

  ////////////////////////////////////////////////////////////////////////
  /// Nodes and links management.
  ////////////////////////////////////////////////////////////////////////

  Map<String, NodePrototype> nodePrototypes = {};
  List<NodePrototype> get nodePrototypesAsList =>
      nodePrototypes.values.map((e) => e).toList();
  int get nodePrototypeCount => nodePrototypes.length;

  Map<String, NodeDataModel> get nodes => project.projectData.nodes;
  List<NodeDataModel> get nodesAsList => nodes.values.toList();
  int get nodeCount => nodes.length;

  Map<String, LinkDataModel> get links => project.projectData.links;
  List<LinkDataModel> get linksAsList =>
      project.projectData.links.values.toList();
  int get linkCount => links.length;

  final SpatialHashGrid nodesSpatialHashGrid = SpatialHashGrid();

  /// This map holds the raw nodes offsets before they are snapped to the grid.
  final Map<String, Offset> unboundNodeOffsets = {};

  bool isNodePresent(String id) => nodes.containsKey(id);
  bool isLinkPresent(String id) => links.containsKey(id);

  bool isNodeSelected(String id) => selectedNodeIds.contains(id);
  bool isLinkSelected(String id) => selectedLinkIds.contains(id);

  NodeDataModel? getNodeById(String id) => nodes[id];
  LinkDataModel? getLinkById(String id) => project.projectData.links[id];

  /// This method is used to register a node prototype with the node editor.
  ///
  /// NOTE: node prototypes are identified by human-readable strings instead of UUIDs.
  void registerNodePrototype(NodePrototype prototype) {
    nodePrototypes.putIfAbsent(
      prototype.idName,
      () => prototype,
    );
  }

  /// This method is used to remove a node prototype by its name.
  ///
  /// NOTE: node prototypes are identified by human-readable strings instead of UUIDs.
  void unregisterNodePrototype(String name) {
    if (!nodePrototypes.containsKey(name)) {
      throw Exception('Node prototype $name does not exist.');
    } else {
      nodePrototypes.remove(name);
    }
  }

  /// This method is used to add a [NodeDataModel] to the node editor by its prototype name.
  ///
  /// The method takes the name of the node prototype and creates an instance of the node
  /// based on the prototype. The method also takes an optional offset parameter to set the
  /// initial position of the node in the node editor. The node is also inserted into the
  /// spatial hash grid for efficient querying of nodes based on their positions
  ///
  /// See [SpatialHashGrid] and [selectNodesByArea].
  ///
  /// Emits an [AddNodeEvent] event.
  NodeDataModel addNode(
    String name, {
    Offset offset = Offset.zero,
    bool? snapToGrid,
  }) {
    if (!nodePrototypes.containsKey(name)) {
      throw Exception('Node prototype $name does not exist.');
    }

    if (snapToGrid ?? config.enableSnapToGrid) {
      offset = Offset(
        (offset.dx / config.snapToGridSize).round() * config.snapToGridSize,
        (offset.dy / config.snapToGridSize).round() * config.snapToGridSize,
      );
    }

    final instance = createNode(
      nodePrototypes[name]!,
      controller: this,
      offset: offset,
    );

    nodes.putIfAbsent(instance.id, () => instance);
    unboundNodeOffsets.putIfAbsent(instance.id, () => instance.offset);

    nodesDataDirty = true;

    eventBus.emit(
      AddNodeEvent(id: const Uuid().v4(), instance),
    );

    return instance;
  }

  /// This method is used to add a node from an existing node object.
  ///
  /// This method is used when loading a project from a file or in copy/paste operations
  /// and preserves all properties of the node object.
  ///
  /// Emits an [AddNodeEvent] event.
  void addNodeFromExisting(
    NodeDataModel node, {
    bool isHandled = false,
    String? eventId,
  }) {
    if (nodes.containsKey(node.id)) return;

    Offset offset = node.offset;

    if (config.enableSnapToGrid) {
      offset = Offset(
        (offset.dx / config.snapToGridSize).round() * config.snapToGridSize,
        (offset.dy / config.snapToGridSize).round() * config.snapToGridSize,
      );
    }

    nodes.putIfAbsent(node.id, () => node.copyWith(offset: offset));

    unboundNodeOffsets.putIfAbsent(node.id, () => node.offset);

    if (node.state.isSelected) selectedNodeIds.add(node.id);

    nodesDataDirty = true;

    eventBus.emit(
      AddNodeEvent(
        id: eventId ?? const Uuid().v4(),
        node,
        isHandled: isHandled,
      ),
    );

    for (final port in node.ports.values) {
      for (final link in port.links) {
        addLinkFromExisting(link, isHandled: isHandled);
      }
    }
  }

  /// This method is used to remove a node by its ID.
  ///
  /// Emits a [RemoveNodeEvent] event.
  void removeNodeById(
    String id, {
    String? eventId,
    bool isHandled = false,
  }) async {
    if (!nodes.containsKey(id)) return;

    final node = nodes[id]!;

    for (final port in node.ports.values) {
      final linksToRemove = port.links.map((link) => link.id).toList();

      for (final linkId in linksToRemove) {
        removeLinkById(linkId, isHandled: true);
      }
    }

    nodes.remove(id);

    selectedNodeIds.remove(id);

    // The links data is set to dirty by the removeLinkById method.
    nodesDataDirty = true;

    eventBus.emit(
      RemoveNodeEvent(
        id: eventId ?? const Uuid().v4(),
        node,
        isHandled: isHandled,
      ),
    );
  }

  /// This method is used to add a link between two ports.
  ///
  /// The method takes the IDs of the two nodes and the two ports and creates a link
  /// between them. The method also checks if the link is valid based on the port types
  /// and the number of links allowed on each port. Moreover, the method enforces the
  /// direction of the link based on the port types, i.e., an output port can only be
  /// connected to an input port guaranteeing that the graph is directed the right way.
  ///
  /// Emits an [AddLinkEvent] event.
  LinkDataModel? addLink(
    String node1Id,
    String port1IdName,
    String node2Id,
    String port2IdName, {
    String? eventId,
    String? label,
  }) {
    // Check for self-links
    if (node1Id == node2Id) return null;

    final node1 = nodes[node1Id];
    final node2 = nodes[node2Id];
    final port1 = node1?.ports[port1IdName];
    final port2 = node2?.ports[port2IdName];
    if (node1 == null || node2 == null || port1 == null || port2 == null) {
      onCallback?.call(
        CallbackType.error,
        'Cannot connect ports because the node or port does not exist',
      );
      return null;
    }

    String getErrorMessage(PortPrototype port1, PortPrototype port2) {
      // display a specific message if they're incompatible because of different types (e.g. control vs data ports)
      if (port1.type != port2.type) {
        return 'Cannot connect a ${port1.type.name} port to a ${port2.type.name} port';
      }

      // display a specific message if they're incompatible because they're both the same direction (e.g. input & input)
      if (port1.direction == port2.direction) {
        return 'Cannot connect two ${port1.direction.name} ports';
      }

      if (port1.dataType != port2.dataType) {
        return "Cannot connect a port of type '${port1.dataType}' to a port of type '${port2.dataType}'";
      }

      // We don't know why they incompatible, so just show a generic error message
      return "These two ports are incompatible";
    }

    if (!port1.prototype.compatibleWith(port2.prototype)) {
      onCallback?.call(
        CallbackType.error,
        getErrorMessage(port1.prototype, port2.prototype),
      );
      return null;
    }

    // if this exact link already exists, don't do anything
    if (port1.links.any(
          (link) =>
              link.endpoints.sourceNodeId == node2Id &&
              link.endpoints.sourcePortId == port2IdName,
        ) ||
        port2.links.any(
          (link) =>
              link.endpoints.sourceNodeId == node1Id &&
              link.endpoints.sourcePortId == port1IdName,
        )) {
      return null;
    }

    late LinkEndpoints endpoints;

    // Determine the order to insert the node references in the link based on the port direction.
    if (port1.prototype.direction == PortDirection.output) {
      endpoints = (
        sourceNodeId: node1Id,
        sourcePortId: port1IdName,
        targetNodeId: node2Id,
        targetPortId: port2IdName,
      );
    } else {
      endpoints = (
        sourceNodeId: node2Id,
        sourcePortId: port2IdName,
        targetNodeId: node1Id,
        targetPortId: port1IdName,
      );
    }

    final link = LinkDataModel(
      id: const Uuid().v4(),
      endpoints: endpoints,
      state: LinkState(),
      label: label,
    );

    port1.links.add(link);
    port2.links.add(link);

    links.putIfAbsent(
      link.id,
      () => link,
    );

    linksDataDirty = true;

    eventBus.emit(
      AddLinkEvent(id: eventId ?? const Uuid().v4(), link),
    );

    return link;
  }

  /// This method is used to add a link from an existing link object.
  ///
  /// This method is used when loading a project from a file or in copy/paste operations
  /// and preserves all properties of the link object.
  ///
  /// Emits an [AddLinkEvent] event.
  void addLinkFromExisting(
    LinkDataModel link, {
    String? eventId,
    bool isHandled = false,
  }) {
    if (links.containsKey(link.id) ||
        !nodes.containsKey(link.endpoints.sourceNodeId) ||
        !nodes.containsKey(link.endpoints.targetNodeId)) {
      return;
    }

    final fromNode = nodes[link.endpoints.sourceNodeId]!;
    final toNode = nodes[link.endpoints.targetNodeId]!;

    if (!fromNode.ports.containsKey(link.endpoints.sourcePortId) ||
        !toNode.ports.containsKey(link.endpoints.targetPortId)) {
      return;
    }

    final fromPort = fromNode.ports[link.endpoints.sourcePortId]!;
    final toPort = toNode.ports[link.endpoints.targetPortId]!;

    if (fromPort.links.any(
          (existing) =>
              existing.id == link.id || existing.endpoints == link.endpoints,
        ) ||
        toPort.links.any(
          (existing) =>
              existing.id == link.id || existing.endpoints == link.endpoints,
        )) {
      return;
    }

    fromPort.links.add(link);
    toPort.links.add(link);

    links.putIfAbsent(
      link.id,
      () => link,
    );

    if (link.state.isSelected) selectedLinkIds.add(link.id);

    linksDataDirty = true;

    eventBus.emit(
      AddLinkEvent(
        id: eventId ?? const Uuid().v4(),
        link,
        isHandled: isHandled,
      ),
    );
  }

  /// Updates a link label and records the change in editor history.
  ///
  /// Emits a [LinkLabelChangeEvent] event.
  void setLinkLabel(
    String linkId,
    String? label, {
    String? eventId,
    bool isHandled = false,
  }) {
    final link = links[linkId];
    if (link == null || link.label == label) return;

    final updatedLink = link.copyWith(label: label);
    links[linkId] = updatedLink;

    final sourcePort =
        nodes[link.endpoints.sourceNodeId]?.ports[link.endpoints.sourcePortId];
    final targetPort =
        nodes[link.endpoints.targetNodeId]?.ports[link.endpoints.targetPortId];
    sourcePort?.links.remove(link);
    sourcePort?.links.add(updatedLink);
    targetPort?.links.remove(link);
    targetPort?.links.add(updatedLink);

    linksDataDirty = true;
    eventBus.emit(
      LinkLabelChangeEvent(
        linkId,
        oldLabel: link.label,
        newLabel: label,
        id: eventId ?? const Uuid().v4(),
        isHandled: isHandled,
      ),
    );
  }

  /// This method is used to remove a link by its ID.
  ///
  /// Emits a [RemoveLinkEvent] event.
  void removeLinkById(
    String id, {
    String? eventId,
    bool isHandled = false,
  }) {
    if (!links.containsKey(id)) return;

    final link = links[id]!;

    // Remove the link from its associated ports
    final fromPort =
        nodes[link.endpoints.sourceNodeId]?.ports[link.endpoints.sourcePortId];
    final toPort =
        nodes[link.endpoints.targetNodeId]?.ports[link.endpoints.targetPortId];

    fromPort?.links.remove(link);
    toPort?.links.remove(link);

    links.remove(id);

    selectedLinkIds.remove(id);

    linksDataDirty = true;

    eventBus.emit(
      RemoveLinkEvent(
        id: eventId ?? const Uuid().v4(),
        link,
        isHandled: isHandled,
      ),
    );
  }

  /// Represents a link in the process of being drawn.
  TempLinkDataModel? _tempLink;
  TempLinkDataModel? get tempLink => _tempLink;

  /// This method is used to draw a temporary link between two points in the node editor.
  ///
  /// Usually, this method is called when the user is dragging a link from a port to another port.
  ///
  /// Emits a [DrawTempLinkEvent] event.
  void drawTempLink(LinkStyle style, Offset from, Offset to) {
    _tempLink = TempLinkDataModel(style: style, from: from, to: to);

    // The temp link is treated differently from regular links, so we don't need to mark the links data as dirty.

    eventBus.emit(DrawTempLinkEvent(id: const Uuid().v4(), from, to));
  }

  /// This method is used to clear the temporary link from the node editor.
  ///
  /// Emits a [DrawTempLinkEvent] event.
  void clearTempLink() {
    _tempLink = null;

    // The temp link is treated differently from regular links, so we don't need to mark the links data as dirty.

    eventBus.emit(
      DrawTempLinkEvent(id: const Uuid().v4(), Offset.zero, Offset.zero),
    );
  }

  /// This method is used to break all links associated with a port.
  ///
  /// Emits a [RemoveLinkEvent] event for each link that is removed.
  void breakPortLinks(String nodeId, String portId, {bool isHandled = false}) {
    if (!nodes.containsKey(nodeId)) return;
    if (!nodes[nodeId]!.ports.containsKey(portId)) return;

    final port = nodes[nodeId]!.ports[portId]!;
    final linksToRemove = port.links.map((link) => link.id).toList();

    for (final linkId in linksToRemove) {
      removeLinkById(linkId, isHandled: linkId != linksToRemove.last);
    }

    linksDataDirty = true;
  }

  /// This method is used to set the data of a field in a node.
  ///
  /// Emits a [NodeFieldEvent] event.
  void setFieldData(
    String nodeId,
    String fieldId, {
    dynamic data,
    required FieldEventType eventType,
  }) {
    final node = nodes[nodeId]!;
    final field = node.fields[fieldId]!;
    field.data = data;

    eventBus.emit(
      NodeFieldEvent(
        id: const Uuid().v4(),
        nodeId,
        data,
        eventType,
      ),
    );
  }

  /// Sets or clears the instance title for a node.
  ///
  /// A null or whitespace-only title restores the prototype display name.
  /// Emits an undoable [NodeRenameEvent] when the title changes.
  void renameNode(
    String nodeId,
    String? title, {
    String? eventId,
    bool isHandled = false,
  }) {
    final node = nodes[nodeId];
    if (node == null) return;

    final normalizedTitle = title?.trim();
    final nextTitle = normalizedTitle?.isEmpty == true ? null : normalizedTitle;
    if (node.customTitle == nextTitle) return;

    final oldTitle = node.customTitle;
    node.customTitle = nextTitle;
    nodesDataDirty = true;

    eventBus.emit(
      NodeRenameEvent(
        nodeId,
        oldTitle: oldTitle,
        newTitle: nextTitle,
        id: eventId ?? const Uuid().v4(),
        isHandled: isHandled,
      ),
    );
  }

  /// Sets a node's fixed size, or clears it when [size] is null.
  ///
  /// The requested dimensions are clamped to [NodeEditorConfig]'s bounds and
  /// the change is recorded as one undoable event.
  void resizeNode(
    String nodeId,
    Size? size, {
    String? eventId,
    bool isHandled = false,
  }) {
    final node = nodes[nodeId];
    if (node == null) return;

    Size? normalizedSize;
    if (size != null) {
      if (!size.width.isFinite ||
          !size.height.isFinite ||
          size.width <= 0 ||
          size.height <= 0) {
        return;
      }
      normalizedSize = Size(
        size.width
            .clamp(
              minimumNodeSizeFor(node).width,
              config.maxNodeWidth,
            )
            .toDouble(),
        size.height
            .clamp(
              minimumNodeSizeFor(node).height,
              config.maxNodeHeight,
            )
            .toDouble(),
      );
    }

    if (node.customSize == normalizedSize) return;

    final oldSize = node.customSize;
    node.customSize = normalizedSize;
    nodesDataDirty = true;
    linksDataDirty = true;

    eventBus.emit(
      NodeResizeEvent(
        nodeId,
        oldSize: oldSize,
        newSize: normalizedSize,
        id: eventId ?? const Uuid().v4(),
        isHandled: isHandled,
      ),
    );
  }

  /// This method is used to toggle the collapse state of all selected nodes.
  ///
  /// Emit a [NodeRenderModeEvent] event.
  void toggleCollapseSelectedNodes(bool collapse) {
    for (final id in selectedNodeIds) {
      final node = nodes[id];
      node?.state.isCollapsed = collapse;
    }

    linksDataDirty = true;
    nodesDataDirty = true;

    eventBus.emit(
      CollapseNodeEvent(id: const Uuid().v4(), collapse, selectedNodeIds),
    );
  }

  ////////////////////////////////////////////////////////////////////////////
  /// Selection management.
  ///////////////////////////////////////////////////////////////////////////

  final Set<String> selectedNodeIds = {};
  final Set<String> selectedLinkIds = {};

  Rect? _highlightArea;
  Rect? get highlightArea => _highlightArea;

  /// This method is used to drag the selected nodes by a given delta affecting their offsets.
  ///
  /// Emits a [DragSelectionEvent] event.
  void dragSelection(
    Offset delta, {
    String? eventId,
    bool isWorldDelta = false,
    bool resetUnboundOffset = false,
  }) async {
    if (selectedNodeIds.isEmpty) return;

    // If the delta is not already in world coordinates,
    // convert it by dividing by the viewport zoom.
    final Offset effectiveDelta = isWorldDelta ? delta : delta / viewportZoom;

    for (final id in selectedNodeIds) {
      final node = nodes[id]!;

      // Reset the unbound offset if requested (e.g. during undo/redo)
      if (resetUnboundOffset) {
        unboundNodeOffsets[id] = node.offset;
      } else {
        unboundNodeOffsets.putIfAbsent(id, () => node.offset);
      }

      // Update the unbound offset by adding the effective delta.
      unboundNodeOffsets[id] = unboundNodeOffsets[id]! + effectiveDelta;

      if (config.enableSnapToGrid) {
        final unboundOffset = unboundNodeOffsets[id]!;

        // Snap the node's offset to the grid using rounding.
        node.offset = Offset(
          (unboundOffset.dx / config.snapToGridSize).round() *
              config.snapToGridSize,
          (unboundOffset.dy / config.snapToGridSize).round() *
              config.snapToGridSize,
        );
      } else {
        // Apply the effective delta directly to the node's offset.
        node.offset += effectiveDelta;
      }
    }

    linksDataDirty = true;
    nodesDataDirty = true;

    // Emit a DragSelectionEvent with the effective delta (in world coordinates).
    eventBus.emit(
      DragSelectionEvent(
        id: eventId ?? const Uuid().v4(),
        selectedNodeIds.toSet(),
        effectiveDelta,
      ),
    );
  }

  /// Moves the selection to the nearest node in [direction].
  ///
  /// Hosts can map keyboard or accessibility actions to this method without
  /// reimplementing node geometry. Returns the selected node ID, or `null`
  /// when there is no current selection or no node in that direction.
  String? navigateSelection(
    NodeNavigationDirection direction, {
    bool extendSelection = false,
    double minPrimaryDistance = 20,
  }) {
    if (selectedNodeIds.isEmpty) return null;

    final current = nodes[selectedNodeIds.last];
    if (current == null) return null;

    final nearest = findNearestNodeInDirection(
      nodes.values,
      current,
      direction,
      minPrimaryDistance: minPrimaryDistance,
    );
    if (nearest == null) return null;

    selectNodesById(
      {nearest.id},
      holdSelection: extendSelection,
    );
    return nearest.id;
  }

  /// This method is used to set the selection area for selecting nodes.
  ///
  /// See [selectNodesByArea] for more information.
  ///
  /// Emits a [highlightAreaEvent] event.
  void setHighlightArea(Rect? area) {
    _highlightArea = area;
    eventBus.emit(AreaHighlightEvent(id: const Uuid().v4(), area));
  }

  /// This method is used to select nodes by their IDs.
  ///
  /// Emits a [NodeSelectionEvent] event.
  void selectNodesById(
    Set<String> ids, {
    bool holdSelection = false,
    bool isHandled = false,
  }) async {
    final validIds = ids.where(nodes.containsKey).toSet();
    if (validIds.isEmpty) {
      return clearSelection();
    } else if (!holdSelection) {
      clearSelection();
    }

    selectedNodeIds.addAll(validIds);

    for (final id in selectedNodeIds) {
      final node = nodes[id];
      node?.state.isSelected = true;
    }

    eventBus.emit(
      NodeSelectionEvent(
        id: const Uuid().v4(),
        selectedNodeIds.toSet(),
        type: holdSelection
            ? SelectionEventType.holdSelect
            : SelectionEventType.select,
        isHandled: isHandled,
      ),
    );
  }

  /// This method is used to select nodes that are contained within the selection area.
  ///
  /// This method is used in conjunction with the [sethighlightArea] method to select
  /// nodes that are contained within the selection area. The method queries the spatial
  /// hash grid to find nodes that are within the selection area and then selects them.
  ///
  /// See [selectNodesById] for more information.
  void selectNodesByArea({bool holdSelection = false}) async {
    if (_highlightArea == null || _highlightArea == Rect.zero) {
      return clearSelection();
    }

    final containedNodes = nodesSpatialHashGrid.queryArea(_highlightArea!);

    selectNodesById(
      containedNodes,
      holdSelection: holdSelection,
    );

    _highlightArea = Rect.zero;
  }

  /// This method is used to select a link by its ID.
  ///
  /// Emits a [NodeSelectionEvent] event.
  void selectLinkById(
    String id, {
    bool holdSelection = false,
    bool isHandled = false,
  }) async {
    if (id.isEmpty || !links.containsKey(id)) {
      return clearSelection();
    } else if (!holdSelection) {
      clearSelection();
    }

    selectedLinkIds.add(id);

    for (final id in selectedLinkIds) {
      final link = links[id];
      link?.state.isSelected = true;
    }

    linksDataDirty = true;

    eventBus.emit(
      LinkSelectionEvent(
        id: const Uuid().v4(),
        selectedLinkIds.toSet(),
        type: holdSelection
            ? SelectionEventType.holdSelect
            : SelectionEventType.select,
        isHandled: isHandled,
      ),
    );
  }

  /// This method is used to deselect all selected nodes.
  void clearSelection({bool isHandled = false}) {
    for (final id in selectedNodeIds) {
      final node = nodes[id];
      node?.state.isSelected = false;
    }

    for (final id in selectedLinkIds) {
      final link = links[id];
      link?.state.isSelected = false;
    }

    linksDataDirty = true;
    nodesDataDirty = true;

    eventBus.emit(
      NodeSelectionEvent(
        id: const Uuid().v4(),
        selectedNodeIds.toSet(),
        type: SelectionEventType.deselect,
        isHandled: isHandled,
      ),
    );

    eventBus.emit(
      LinkSelectionEvent(
        id: const Uuid().v4(),
        selectedLinkIds.toSet(),
        type: SelectionEventType.deselect,
        isHandled: isHandled,
      ),
    );

    selectedNodeIds.clear();
    selectedLinkIds.clear();
  }

  /// Selects every node currently in the project.
  void selectAllNodes({bool holdSelection = false}) {
    selectNodesById(nodes.keys.toSet(), holdSelection: holdSelection);
  }

  /// Replaces the current node selection with its inverse.
  void invertNodeSelection() {
    final nextSelection =
        nodes.keys.where((id) => !selectedNodeIds.contains(id)).toSet();
    selectNodesById(nextSelection);
  }

  /// Removes all selected nodes and links, then clears the selection.
  void deleteSelection() {
    final selectedNodes = selectedNodeIds.toList();
    final selectedLinks = selectedLinkIds.toList();

    for (final nodeId in selectedNodes) {
      removeNodeById(
        nodeId,
        isHandled: nodeId != selectedNodes.last,
      );
    }
    for (final linkId in selectedLinks) {
      removeLinkById(linkId, isHandled: linkId != selectedLinks.last);
    }
    clearSelection();
  }

  void alignSelectedNodes(NodeAlignment alignment) {
    final selected = selectedNodeIds
        .map((id) => nodes[id])
        .whereType<NodeDataModel>()
        .toList();
    if (selected.length < 2) return;

    final sizes = {
      for (final node in selected) node.id: _renderedNodeSize(node),
    };
    final value = switch (alignment) {
      NodeAlignment.left => selected.map((node) => node.offset.dx).reduce(min),
      NodeAlignment.centerHorizontal => selected
              .map((node) => node.offset.dx + sizes[node.id]!.width / 2)
              .reduce((a, b) => a + b) /
          selected.length,
      NodeAlignment.right => selected
          .map((node) => node.offset.dx + sizes[node.id]!.width)
          .reduce(max),
      NodeAlignment.top => selected.map((node) => node.offset.dy).reduce(min),
      NodeAlignment.centerVertical => selected
              .map((node) => node.offset.dy + sizes[node.id]!.height / 2)
              .reduce((a, b) => a + b) /
          selected.length,
      NodeAlignment.bottom => selected
          .map((node) => node.offset.dy + sizes[node.id]!.height)
          .reduce(max),
    };

    final positions = <String, Offset>{};
    for (final node in selected) {
      final size = sizes[node.id]!;
      positions[node.id] = switch (alignment) {
        NodeAlignment.left => Offset(value, node.offset.dy),
        NodeAlignment.centerHorizontal =>
          Offset(value - size.width / 2, node.offset.dy),
        NodeAlignment.right => Offset(value - size.width, node.offset.dy),
        NodeAlignment.top => Offset(node.offset.dx, value),
        NodeAlignment.centerVertical =>
          Offset(node.offset.dx, value - size.height / 2),
        NodeAlignment.bottom => Offset(node.offset.dx, value - size.height),
      };
    }
    applyLayout(positions);
  }

  Size _renderedNodeSize(NodeDataModel node) {
    final renderSize = RenderBoxUtils.getSizeFromGlobalKey(node.key);
    return renderSize ?? node.customSize ?? Size.zero;
  }

  void distributeSelectedNodes(NodeDistributionAxis axis) {
    final selected = selectedNodeIds
        .map((id) => nodes[id])
        .whereType<NodeDataModel>()
        .toList();
    if (selected.length < 3) return;

    selected.sort(
      (a, b) => axis == NodeDistributionAxis.horizontal
          ? a.offset.dx.compareTo(b.offset.dx)
          : a.offset.dy.compareTo(b.offset.dy),
    );
    final first = axis == NodeDistributionAxis.horizontal
        ? selected.first.offset.dx
        : selected.first.offset.dy;
    final last = axis == NodeDistributionAxis.horizontal
        ? selected.last.offset.dx
        : selected.last.offset.dy;
    final step = (last - first) / (selected.length - 1);

    final positions = <String, Offset>{};
    for (var index = 1; index < selected.length - 1; index++) {
      final node = selected[index];
      final position = first + step * index;
      positions[node.id] = axis == NodeDistributionAxis.horizontal
          ? Offset(position, node.offset.dy)
          : Offset(node.offset.dx, position);
    }
    applyLayout(positions);
  }

  /// Applies multiple node positions as one editor operation.
  ///
  /// A single [NodeLayoutEvent] is emitted and recorded in history, so
  /// alignment, distribution, auto-layout, and host-provided layout commands
  /// can be undone in one step.
  void applyLayout(
    Map<String, Offset> positions, {
    String? eventId,
    bool isHandled = false,
  }) {
    final previousPositions = <String, Offset>{};
    final nextPositions = <String, Offset>{};
    for (final entry in positions.entries) {
      final node = nodes[entry.key];
      if (node == null || node.offset == entry.value) continue;
      previousPositions[entry.key] = node.offset;
      nextPositions[entry.key] = entry.value;
    }
    if (nextPositions.isEmpty) return;

    for (final entry in nextPositions.entries) {
      final node = nodes[entry.key]!;
      node.offset = entry.value;
      unboundNodeOffsets[node.id] = entry.value;
    }

    nodesDataDirty = true;
    linksDataDirty = true;
    eventBus.emit(
      NodeLayoutEvent(
        nextPositions.keys.toSet(),
        id: eventId ?? const Uuid().v4(),
        isHandled: isHandled,
        previousPositions: previousPositions,
        nextPositions: nextPositions,
      ),
    );
  }

  /////////////////////////////////////////////////////////////////////
  /// Miscellaneous helpers useful for node editors.
  /////////////////////////////////////////////////////////////////////

  /// This method is used to focus the viweport on a set of nodes by their IDs.
  ///
  /// The method calculates the encompassing rectangle of the nodes and then
  /// centers the viewport on the center of the rectangle. The method also
  /// calculates the zoom level required to fit all the nodes in the viewport.
  ///
  /// See [calculateEncompassingRect], [selectNodesById], [setViewportOffset], and [setViewportZoom] for more information.
  void focusNodesById(
    Set<String> ids, {
    bool holdSelection = false,
    bool animate = true,
  }) {
    selectNodesById(ids, holdSelection: holdSelection);

    if (selectedNodeIds.isEmpty) return;

    final nodeEditorSize = RenderBoxUtils.getSizeFromGlobalKey(editorKey);
    if (nodeEditorSize == null || nodeEditorSize.isEmpty) return;

    final encompassingRect = NodeEditorUtils.calculateEncompassingRect(
      selectedNodeIds,
      nodes,
      margin: 256,
    );

    if (encompassingRect.isEmpty) return;

    setViewportOffset(
      -encompassingRect.center,
      animate: animate,
      absolute: true,
    );

    final fitZoom = min(
      nodeEditorSize.width / encompassingRect.width,
      nodeEditorSize.height / encompassingRect.height,
    );

    setViewportZoom(
      fitZoom,
      absolute: true,
      animate: animate,
    );
  }

  /// Centers the viewport on all nodes without changing their selection.
  void focusAllNodes({bool animate = true}) {
    final previousSelection = selectedNodeIds.toSet();
    focusNodesById(nodes.keys.toSet(), animate: animate);
    selectNodesById(previousSelection);
  }

  /// Restores the default centered viewport and zoom.
  void resetViewport({bool animate = true}) {
    setViewportOffset(Offset.zero, absolute: true, animate: animate);
    setViewportZoom(1.0, absolute: true, animate: animate);
  }

  /// This method is used to find all nodes with the specified display name.
  Future<List<String>> searchNodesByName(
    BuildContext context,
    String name,
  ) async {
    final results = <String>[];

    final regex = RegExp(name, caseSensitive: false);

    for (final node in nodes.values) {
      if (regex.hasMatch(node.prototype.displayName(context))) {
        results.add(node.id);
      }
    }

    return results;
  }
}

enum NodeAlignment {
  left,
  centerHorizontal,
  right,
  top,
  centerVertical,
  bottom,
}

enum NodeDistributionAxis { horizontal, vertical }
