import '../events/events.dart';

/// Identifies events that change data persisted in a node-editor project.
///
/// Selection, hover, viewport, styling, and temporary drawing events are
/// intentionally excluded so hosts can use this policy for dirty-state
/// tracking without duplicating the event taxonomy.
bool isNodeEditorContentMutation(NodeEditorEvent event) =>
    event is AddLinkEvent ||
    event is RemoveLinkEvent ||
    event is NodeResizeEvent ||
    event is NodeRenameEvent ||
    event is LinkLabelChangeEvent ||
    event is DragSelectionEvent ||
    event is AddNodeEvent ||
    event is RemoveNodeEvent ||
    event is PasteSelectionEvent ||
    event is CutSelectionEvent ||
    event is NodeLayoutEvent ||
    (event is NodeFieldEvent && event.eventType != FieldEventType.change);
