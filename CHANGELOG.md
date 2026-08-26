# Changelog

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
