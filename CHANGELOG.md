# Changelog

## Unreleased

- Added atomic graph splicing and generic frame/group operations with undo/redo support.
- Fixed node resizing dragging the node simultaneously and scaling movement
  twice at non-default zoom levels; covered by desktop pointer tests.
- Directional navigation now compares rendered node centers, including resized
  nodes. Arrow shortcuts work without a host callback.
- Added fit/reset/zoom keyboard shortcuts and a live toolbar zoom percentage.

## 0.2.2

- Removed the development-only viewport border, origin marker, and debug
  metrics from the editor surface.
- Made primary-button dragging on the canvas pan the viewport; hold Shift for
  area selection.
- Hardened desktop pointer handling for node selection and combined mouse
  button states.

## 0.2.1

- Added generic directional selection navigation.
- Added viewport coordinate transforms for screen/world conversion and visible
  bounds calculations.
- Added a content revision notifier for host dirty-state tracking.
- Added atomic, undoable multi-node layout operations.
- Added an opt-in JSON extension payload for host-owned clipboard metadata.

## 0.2.0

- Breaking: renamed link endpoint APIs to `LinkEndpoints endpoints` with
  `sourceNodeId`, `sourcePortId`, `targetNodeId`, and `targetPortId` fields.
- Breaking: link JSON now uses the semantic endpoint field names.
- Added optional link labels with JSON persistence, configurable rendering, and
  undoable updates through `setLinkLabel`.
- Updated the `flutter_context_menu` integration to the 0.4.2 API.
- Exported the public callback, project, selection, and link-label event types.
- Fixed field change events so `setFieldData` updates the field and emits the
  corresponding `NodeFieldEvent`.
- Exported the `NodeEditorEvent` base type from the public package API.

## 0.1.0

Initial SAI Nodes release for reusable Flutter workflow, dataflow, and shader
graph editors.

- Added the node, port, link, selection, viewport, history, clipboard, and
  project persistence APIs.
- Added customizable node, field, port, header, and context-menu builders.
- Added controller reliability fixes for clearing projects, invalid links,
  stale selections, duplicate links, and complete configuration copying.
- Removed the inherited `Fl` API prefix in favor of neutral public names such as
  `NodeEditorController` and `LinkDataModel`.
- Updated the renderer to use current `vector_math` transformation APIs.
