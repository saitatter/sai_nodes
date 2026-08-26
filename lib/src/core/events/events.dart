import 'package:sai_nodes/src/core/controller/core.dart';
import 'package:sai_nodes/src/core/controller/project.dart';
import 'package:sai_nodes/src/core/models/data.dart';
import 'package:sai_nodes/src/styles/styles.dart';
import 'package:flutter/material.dart';

///
/// It includes an [id] to identify the event, a [isHandled] flag to indicate if the event has been handled,
/// and an [isUndoable] flag to indicate if the event can be undone.
@immutable
abstract base class NodeEditorEvent {
  final String id;
  final bool isHandled;
  final bool isUndoable;

  const NodeEditorEvent({
    required this.id,
    this.isHandled = false,
    this.isUndoable = false,
  });

  Map<String, dynamic> toJson(Map<String, DataHandler> dataHandlers) => {
        'id': id,
        'isHandled': isHandled,
        'isUndoable': isUndoable,
      };
}

////////////////////////////////////////////////////////////////////////
/// Viewport events.
////////////////////////////////////////////////////////////////////////

/// Event produced when the viewport offset changes.
final class ViewportOffsetEvent extends NodeEditorEvent {
  final Offset offset;
  final bool animate;

  const ViewportOffsetEvent(
    this.offset, {
    this.animate = true,
    required super.id,
    super.isHandled,
  });
}

/// Event produced when the viewport zoom level changes.
final class ViewportZoomEvent extends NodeEditorEvent {
  final double zoom;
  final bool animate;

  const ViewportZoomEvent(
    this.zoom, {
    this.animate = true,
    required super.id,
    super.isHandled,
  });
}

////////////////////////////////////////////////////////////////////////
/// Selection events.
////////////////////////////////////////////////////////////////////////

enum SelectionEventType {
  select,
  holdSelect,
  deselect,
}

/// Event produced when nodes are selected or deselected.
final class NodeSelectionEvent extends NodeEditorEvent {
  final SelectionEventType type;
  final Set<String> nodeIds;

  const NodeSelectionEvent(
    this.nodeIds, {
    required this.type,
    required super.id,
    super.isHandled,
  });
}

/// Event produced when the user starts dragging a group of selected nodes.
final class DragSelectionStartEvent extends NodeEditorEvent {
  final Set<String> nodeIds;
  final Offset position;

  const DragSelectionStartEvent(
    this.nodeIds,
    this.position, {
    required super.id,
    super.isHandled,
  });

  @override
  Map<String, dynamic> toJson(dataHandlers) => {
        ...super.toJson(dataHandlers),
        'nodeIds': nodeIds.toList(),
        'position': [position.dx, position.dy],
      };

  factory DragSelectionStartEvent.fromJson(Map<String, dynamic> json) {
    return DragSelectionStartEvent(
      (json['nodeIds'] as List).cast<String>().toSet(),
      Offset(json['position'][0], json['position'][1]),
      id: json['id'] as String,
      isHandled: json['isHandled'] as bool,
    );
  }
}

/// Event produced to update the position of a group of selected nodes while dragging.
final class DragSelectionEvent extends NodeEditorEvent {
  final Set<String> nodeIds;
  final Offset delta;

  const DragSelectionEvent(
    this.nodeIds,
    this.delta, {
    required super.id,
    super.isHandled,
  }) : super(isUndoable: true);

  @override
  Map<String, dynamic> toJson(dataHandlers) => {
        ...super.toJson(dataHandlers),
        'nodeIds': nodeIds.toList(),
        'delta': [delta.dx, delta.dy],
      };

  factory DragSelectionEvent.fromJson(Map<String, dynamic> json) {
    return DragSelectionEvent(
      (json['nodeIds'] as List).cast<String>().toSet(),
      Offset(json['delta'][0], json['delta'][1]),
      id: json['id'] as String,
      isHandled: json['isHandled'] as bool,
    );
  }
}

/// Event produced when the user stops dragging a group of selected nodes.
final class DragSelectionEndEvent extends NodeEditorEvent {
  final Offset position;
  final Set<String> nodeIds;

  const DragSelectionEndEvent(
    this.position,
    this.nodeIds, {
    required super.id,
    super.isHandled,
  });

  @override
  Map<String, dynamic> toJson(dataHandlers) => {
        ...super.toJson(dataHandlers),
        'position': [position.dx, position.dy],
        'nodeIds': nodeIds.toList(),
      };

  factory DragSelectionEndEvent.fromJson(Map<String, dynamic> json) {
    return DragSelectionEndEvent(
      Offset(json['position'][0], json['position'][1]),
      (json['nodeIds'] as List).cast<String>().toSet(),
      id: json['id'] as String,
      isHandled: json['isHandled'] as bool,
    );
  }
}

/// Event produced when the user selects or deselects a group of links (one or more).
final class LinkSelectionEvent extends NodeEditorEvent {
  final SelectionEventType type;
  final Set<String> linkIds;

  const LinkSelectionEvent(
    this.linkIds, {
    required this.type,
    required super.id,
    super.isHandled,
  });
}

/// Event produced when the user copies a selection to the clipboard (Ctrl+C).
final class CopySelectionEvent extends NodeEditorEvent {
  final String clipboardContent;

  const CopySelectionEvent(
    this.clipboardContent, {
    required super.id,
    super.isHandled,
  }) : super(isUndoable: true);
}

/// Event produced when the user pastes a selection from the clipboard (Ctrl+V).
final class PasteSelectionEvent extends NodeEditorEvent {
  final Offset position;
  final String clipboardContent;

  const PasteSelectionEvent(
    this.position,
    this.clipboardContent, {
    required super.id,
    super.isHandled,
  });
}

/// Event produced when the user cuts a selection to the clipboard (Ctrl+X).
final class CutSelectionEvent extends NodeEditorEvent {
  final String clipboardContent;

  const CutSelectionEvent(
    this.clipboardContent, {
    required super.id,
    super.isHandled,
  });
}

////////////////////////////////////////////////////////////////////////
/// Hover events.
////////////////////////////////////////////////////////////////////////

enum HoverEventType {
  enter,
  exit,
}

/// Event produced when the user enters or exits the bounds of a node.
final class NodeHoverEvent extends NodeEditorEvent {
  final HoverEventType type;
  final String nodeId;

  const NodeHoverEvent(
    this.nodeId, {
    required this.type,
    required super.id,
    super.isHandled,
  });
}

// NOTE: We don't have hover events for links and ports because they are not widgets and therefore
// they do not require state management and are managed directly in the render object. Moreover,
// hover events in general cannot be produced from the controller.

////////////////////////////////////////////////////////////////////////
/// Nodes, groups and links management events.
////////////////////////////////////////////////////////////////////////

/// Event produced when the user creates a new node.
final class AddNodeEvent extends NodeEditorEvent {
  final NodeDataModel node;

  const AddNodeEvent(
    this.node, {
    required super.id,
    super.isHandled,
  }) : super(isUndoable: true);

  @override
  Map<String, dynamic> toJson(dataHandlers) => {
        ...super.toJson(dataHandlers),
        'node': node.toJson(dataHandlers),
      };

  factory AddNodeEvent.fromJson(
    Map<String, dynamic> json, {
    required NodeEditorController controller,
  }) {
    return AddNodeEvent(
      NodeDataModel.fromJson(
        json['node'] as Map<String, dynamic>,
        nodePrototypes: controller.nodePrototypes,
        dataHandlers: controller.project.dataHandlers,
      ),
      id: json['id'] as String,
      isHandled: json['isHandled'] as bool,
    );
  }
}

/// Event produced when the user removes a node.
final class RemoveNodeEvent extends NodeEditorEvent {
  final NodeDataModel node;

  const RemoveNodeEvent(this.node, {required super.id, super.isHandled})
      : super(isUndoable: true);

  @override
  Map<String, dynamic> toJson(dataHandlers) => {
        ...super.toJson(dataHandlers),
        'node': node.toJson(dataHandlers),
      };

  factory RemoveNodeEvent.fromJson(
    Map<String, dynamic> json, {
    required NodeEditorController controller,
  }) {
    return RemoveNodeEvent(
      NodeDataModel.fromJson(
        json['node'] as Map<String, dynamic>,
        nodePrototypes: controller.nodePrototypes,
        dataHandlers: controller.project.dataHandlers,
      ),
      id: json['id'] as String,
      isHandled: json['isHandled'] as bool,
    );
  }
}

/// Event produced when the creates a new link between two nodes.
final class AddLinkEvent extends NodeEditorEvent {
  final LinkDataModel link;

  const AddLinkEvent(
    this.link, {
    required super.id,
    super.isHandled,
  }) : super(isUndoable: true);

  @override
  Map<String, dynamic> toJson(dataHandlers) => {
        ...super.toJson(dataHandlers),
        'link': link.toJson(),
      };

  factory AddLinkEvent.fromJson(Map<String, dynamic> json) {
    return AddLinkEvent(
      LinkDataModel.fromJson(json['link'] as Map<String, dynamic>),
      id: json['id'] as String,
      isHandled: json['isHandled'] as bool,
    );
  }
}

/// Event produced when the user removes a link between two nodes.
final class RemoveLinkEvent extends NodeEditorEvent {
  final LinkDataModel link;

  const RemoveLinkEvent(this.link, {required super.id, super.isHandled})
      : super(isUndoable: true);

  @override
  Map<String, dynamic> toJson(dataHandlers) => {
        ...super.toJson(dataHandlers),
        'link': link.toJson(),
      };

  factory RemoveLinkEvent.fromJson(Map<String, dynamic> json) {
    return RemoveLinkEvent(
      LinkDataModel.fromJson(json['link'] as Map<String, dynamic>),
      id: json['id'] as String,
      isHandled: json['isHandled'] as bool,
    );
  }
}

/// Event produced when the user collapses or expands a group of nodes (can be used for any widget changes that require layout updates).
final class CollapseNodeEvent extends NodeEditorEvent {
  final bool collpased;
  final Set<String> nodeIds;

  const CollapseNodeEvent(
    this.collpased,
    this.nodeIds, {
    required super.id,
    super.isHandled,
  });
}

enum FieldEventType {
  change,
  submit,
  cancel,
}

/// Event produced when the user changes a field value in a node.
final class NodeFieldEvent extends NodeEditorEvent {
  final String nodeId;
  final dynamic value;
  final FieldEventType eventType;

  const NodeFieldEvent(
    this.nodeId,
    this.value,
    this.eventType, {
    required super.id,
    super.isHandled,
  });
}

////////////////////////////////////////////////////////////////////////
/// Project management events.
////////////////////////////////////////////////////////////////////////

/// Event produced when the user saves the current project (Ctrl+S).
final class SaveProjectEvent extends NodeEditorEvent {
  const SaveProjectEvent({required super.id});
}

/// Event produced when the user loads a project (Ctrl+O).
final class LoadProjectEvent extends NodeEditorEvent {
  const LoadProjectEvent({required super.id});
}

/// Event produced when the user creates a new project (Ctrl+Shift+N).
final class NewProjectEvent extends NodeEditorEvent {
  const NewProjectEvent({required super.id});
}

////////////////////////////////////////////////////////////////////////
/// Temporary drawing events.
////////////////////////////////////////////////////////////////////////

/// Event produced to update the path of the link being drawn when the user drags from a port to create a new link.
final class DrawTempLinkEvent extends NodeEditorEvent {
  final Offset from;
  final Offset to;

  const DrawTempLinkEvent(
    this.from,
    this.to, {
    required super.id,
    super.isHandled,
  });
}

/// Event produced when an area is highlighted in the editor viewport (leads to selection).
final class AreaHighlightEvent extends NodeEditorEvent {
  final Rect? area;

  const AreaHighlightEvent(this.area, {required super.id, super.isHandled});
}

/// Event produced when the user changes the configuration of the node editor.
final class ConfigurationChangeEvent extends NodeEditorEvent {
  final NodeEditorConfig config;

  const ConfigurationChangeEvent(this.config, {required super.id});
}

/// Event produced when the user changes the style of the node editor.
final class StyleChangeEvent extends NodeEditorEvent {
  final NodeEditorStyle style;

  const StyleChangeEvent(this.style, {required super.id});
}

/// Event produced when the user changes the locale of the node editor.
final class LocaleChangeEvent extends NodeEditorEvent {
  final Locale locale;

  const LocaleChangeEvent(this.locale, {required super.id});
}
