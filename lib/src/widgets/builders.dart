import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';

import '../../sai_nodes.dart';

/// This file contains all the builders that can be used to fully customize the look of the package.

/// The style of the node header.
///
/// The header is the top part of the node that contains the title and the collapse button.
typedef NodeHeaderBuilder = Widget Function(
  BuildContext context,
  NodeDataModel node,
  NodeStyle style,
  VoidCallback onToggleCollapse,
);

/// The style of the node fields.
///
/// The fields are the widgets that display and allow to edit the data of the node.
typedef NodeFieldBuilder = Widget Function(
  BuildContext context,
  FieldDataModel field,
  NodeStyle style,
);

/// The style of the node ports.
///
/// The ports are the origin and destination points of the links.
typedef NodePortBuilder = Widget Function(
  BuildContext context,
  PortDataModel port,
  NodeStyle style,
);

/// The content of the node context menu.
///
/// The context menu is the menu that appears when the user right-clicks (content depends on the entity being clicked).
typedef NodeContextMenuBuilder = List<ContextMenuEntry> Function(
  BuildContext context,
  NodeDataModel node,
);

/// The content of the editor context menu shown on the empty canvas.
typedef EditorContextMenuBuilder = List<ContextMenuEntry> Function(
  BuildContext context,
  Offset position,
  List<ContextMenuEntry> defaultEntries,
);

/// The style of the node.
///
/// The node is the widget that contains the header, the fields and the ports.
///
/// WARNING: Only use this builder if you want to fully customize the look of the node.
typedef NodeBuilder = Widget Function(
  BuildContext context,
  NodeDataModel node,
);

/// Called after a desktop double-click on a node. Hosts can use this for
/// domain-specific actions such as opening a subgraph or inline editor.
typedef NodeDoubleTapCallback = void Function(
  BuildContext context,
  NodeDataModel node,
);

/// Builds an optional resize handle for a node.
///
/// The callback receives a size in the node's logical coordinate space.
typedef NodeResizeBuilder = Widget Function(
  BuildContext context,
  NodeDataModel node,
  void Function(Size size) onResize,
);
