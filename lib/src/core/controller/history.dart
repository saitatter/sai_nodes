import 'dart:async';

import 'package:sai_nodes/src/core/models/data.dart';

import '../../constants.dart';
import '../events/events.dart';
import '../utils/dsa/stack.dart';
import 'core.dart';

/// A class that manages the undo and redo history of the node editor.
///
/// The undo and redo stacks are capped at [kMaxEventUndoHistory] and
/// [kMaxEventRedoHistory] respectively.
///
/// The history is updated whenever an undoable event is triggered.
class NodeEditorHistoryHelper {
  final NodeEditorController controller;

  bool _isTraversingHistory = false;
  final _undoStack = Stack<NodeEditorEvent>(kMaxEventUndoHistory);
  final _redoStack = Stack<NodeEditorEvent>(kMaxEventRedoHistory);
  late final StreamSubscription<NodeEditorEvent> _eventSubscription;

  NodeEditorHistoryHelper(this.controller) {
    _eventSubscription = controller.eventBus.events.listen(
      _handleUndoableEvents,
    );
  }

  bool get canUndo => !_undoStack.isEmpty;
  bool get canRedo => !_redoStack.isEmpty;

  /// Clears the undo and redo stacks.
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }

  void dispose() {
    _eventSubscription.cancel();
    clear();
  }

  /// Handles undoable events.
  ///
  /// If the event is not undoable, it is ignored.
  ///
  /// If the event is undoable and is not the same as the previous event,
  /// the redo stack is cleared as the user has made a new change.
  /// If the event is a [DragSelectionEvent] and the previous event is also a
  /// [DragSelectionEvent] with the same node IDs, the previous event is popped
  /// and a new [DragSelectionEvent] is pushed after adding the deltas.
  void _handleUndoableEvents(NodeEditorEvent event) {
    if (!event.isUndoable || _isTraversingHistory) return;

    if (_undoStack.length >= kMaxEventUndoHistory) _undoStack.evict();
    if (_redoStack.length >= kMaxEventRedoHistory) _redoStack.evict();

    final previousEvent = _undoStack.peek();
    final nextEvent = _redoStack.peek();

    if (event.id != previousEvent?.id && event.id != nextEvent?.id) {
      _redoStack.clear();
    } else {
      return;
    }

    if (event is DragSelectionEvent && previousEvent is DragSelectionEvent) {
      if (event.nodeIds.length == previousEvent.nodeIds.length &&
          event.nodeIds.every(previousEvent.nodeIds.contains)) {
        _undoStack.pop();
        _undoStack.push(
          DragSelectionEvent(
            id: event.id,
            event.nodeIds,
            event.delta + previousEvent.delta,
          ),
        );
        return;
      }
    }

    if (event is NodeResizeEvent && previousEvent is NodeResizeEvent) {
      if (event.nodeId == previousEvent.nodeId) {
        _undoStack.pop();
        _undoStack.push(
          NodeResizeEvent(
            event.nodeId,
            oldSize: previousEvent.oldSize,
            newSize: event.newSize,
            id: event.id,
          ),
        );
        return;
      }
    }

    _undoStack.push(event);
  }

  /// Undoes the last event in the undo stack.
  void undo() {
    if (_undoStack.isEmpty) return;

    _isTraversingHistory = true;
    final event = _undoStack.pop()!;
    _redoStack.push(event);

    try {
      if (event is DragSelectionEvent) {
        controller.selectNodesById(event.nodeIds, isHandled: true);
        controller.dragSelection(
          -event.delta,
          eventId: event.id,
          isWorldDelta: true,
          resetUnboundOffset: true,
        );
        controller.clearSelection();
      } else if (event is AddNodeEvent) {
        controller.removeNodeById(event.node.id, eventId: event.id);
      } else if (event is RemoveNodeEvent) {
        controller.addNodeFromExisting(event.node, eventId: event.id);
      } else if (event is NodeRenameEvent) {
        controller.renameNode(
          event.nodeId,
          event.oldTitle,
          eventId: event.id,
          isHandled: true,
        );
      } else if (event is NodeResizeEvent) {
        controller.resizeNode(
          event.nodeId,
          event.oldSize,
          eventId: event.id,
          isHandled: true,
        );
      } else if (event is LinkLabelChangeEvent) {
        controller.setLinkLabel(
          event.linkId,
          event.oldLabel,
          eventId: event.id,
          isHandled: true,
        );
      } else if (event is AddLinkEvent) {
        controller.removeLinkById(event.link.id, eventId: event.id);
      } else if (event is RemoveLinkEvent) {
        controller.addLinkFromExisting(event.link, eventId: event.id);
      } else if (event is NodeLayoutEvent) {
        controller.applyLayout(
          event.previousPositions,
          eventId: event.id,
          isHandled: true,
        );
      } else if (event is NodePortsChangeEvent) {
        controller.restoreNodePorts(event, forward: false);
      } else if (event is SpliceNodeEvent) {
        controller.restoreSplice(event, forward: false);
      } else if (event is NodeFrameChangeEvent) {
        controller.restoreFrameSnapshot(
          event.frameId,
          event.previousFrame,
          eventId: event.id,
        );
      }
    } finally {
      _isTraversingHistory = false;
    }
  }

  /// Redoes the last event in the redo stack.
  void redo() {
    if (_redoStack.isEmpty) return;

    _isTraversingHistory = true;
    final event = _redoStack.pop()!;
    _undoStack.push(event);

    try {
      if (event is DragSelectionEvent) {
        controller.selectNodesById(event.nodeIds, isHandled: true);
        controller.dragSelection(
          event.delta,
          eventId: event.id,
          isWorldDelta: true,
          resetUnboundOffset: true,
        );
        controller.clearSelection();
      } else if (event is AddNodeEvent) {
        controller.addNodeFromExisting(
          event.node.copyWith(
            state: NodeState(isSelected: true),
          ),
          eventId: event.id,
        );
      } else if (event is RemoveNodeEvent) {
        controller.removeNodeById(event.node.id, eventId: event.id);
      } else if (event is NodeRenameEvent) {
        controller.renameNode(
          event.nodeId,
          event.newTitle,
          eventId: event.id,
          isHandled: true,
        );
      } else if (event is NodeResizeEvent) {
        controller.resizeNode(
          event.nodeId,
          event.newSize,
          eventId: event.id,
          isHandled: true,
        );
      } else if (event is LinkLabelChangeEvent) {
        controller.setLinkLabel(
          event.linkId,
          event.newLabel,
          eventId: event.id,
          isHandled: true,
        );
      } else if (event is AddLinkEvent) {
        controller.addLinkFromExisting(
          event.link.copyWith(
            state: LinkState(isSelected: true),
          ),
          eventId: event.id,
        );
      } else if (event is RemoveLinkEvent) {
        controller.removeLinkById(
          event.link.id,
          eventId: event.id,
        );
      } else if (event is NodeLayoutEvent) {
        controller.applyLayout(
          event.nextPositions,
          eventId: event.id,
          isHandled: true,
        );
      } else if (event is NodePortsChangeEvent) {
        controller.restoreNodePorts(event, forward: true);
      } else if (event is SpliceNodeEvent) {
        controller.restoreSplice(event, forward: true);
      } else if (event is NodeFrameChangeEvent) {
        controller.restoreFrameSnapshot(
          event.frameId,
          event.nextFrame,
          eventId: event.id,
        );
      }
    } finally {
      _isTraversingHistory = false;
    }
  }
}
