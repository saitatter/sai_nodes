# Graph authoring API

Create a `NodeDefinitionRegistry`, register declarative definitions, and pass a
`GraphDocument` and `GraphResolver` into `GraphController`. `sai_nodes_core` runs
without Flutter; `sai_nodes` exports these primitives plus the Flutter scene and
`NodeEditor` widget. The root `example` demonstrates the new API.

Definitions compose `StaticPortFamily`, `DynamicPortFamily`, `StaticFieldFamily`
and `DynamicFieldFamily`. Resolvers receive read-only document, space, node,
indexes, registry lookup and previous-pass structures. Accesses are tracked for
cache invalidation. Definition callbacks must be deterministic and must not
mutate the registry or execute application actions. Fields use stable data paths;
port IDs are unique across both directions. Use IDs such as `value.in/out` even
when both labels are `Value`.

Issue commands with `controller.execute` or group them with:

```dart
controller.transaction((tx) {
  tx.execute(AddNodeCommand(spaceId, node, presentation: presentation));
  tx.execute(AddConnectionCommand(spaceId, connection));
}, label: 'Create and connect');
```

The controller publishes a resolved document, indexes and `GraphDocumentChange`
synchronously after validation. A failed operation leaves document, revisions
and history unchanged. New connections validate by default. Loaded or explicitly
allowed invalid connections remain representable. Dynamic changes preserve
invalid connections by default. Registry changes re-resolve affected structures.

Use `revision`, `semanticRevision`, `isDirty` and `markSaved`. Undo/redo restore
snapshot revision tokens, so undoing back to a saved state clears dirty status.
Supply a unique `coalesceKey` for a drag or resize session. Persistent changes
produce one history entry/notification per transaction; selection, camera and
execution snapshots are ephemeral. Document listeners must not initiate nested
mutations while a commit is being notified.

`GraphFragment.capture/encode/decode` and `pasteGraphFragment` implement clipboard
mechanics. Paste accepts an ID factory and host enrichment hook, offsets
presentation, remaps every entity and commits atomically. Helpers also support
duplication, deletion, splice, frame movement, alignment and distribution.

`NodeEditor` accepts node, port, field, frame, comment and context-menu builders,
host overlays and an async `onCreateNode` picker. Custom builders receive immutable
models. Generic definition data never contains Flutter widgets. The host owns
complex configuration and application execution. Default controls use typed
fields; custom field builders may expose resource selectors and inspectors.

Canvas shortcuts include Ctrl/Cmd+A/C/X/V/D, Undo/Redo, Delete, arrow navigation
and F to focus. Editable text keeps its own shortcuts. Middle drag or Space+drag
pans; wheel zoom anchors to the pointer; Shift+wheel pans. Port drag connects;
dragging an occupied input reroutes its connection. Double click an edge to add
a waypoint, drag selected waypoints to move them, and use the context menu to
remove a waypoint/reset its route/edit its label. Double click a header to
collapse, or a comment to edit. Context actions create frames/comments or splice
a picked node into an edge. Resize using entity lower-right corners. Frame
metadata can set `membership: contains`; `autoFit` follows member geometry with
optional nonnegative `padding` metadata (default 24).

`GraphSceneBuilder` and its spatial indexes share geometry between rendering,
hit testing, marquee, minimap and execution. Focused/dragged nodes stay mounted
when outside the viewport. `GraphExecutionVisualController.apply` accepts an
immutable snapshot and repaints execution visuals independently of node content.
It never changes graph revisions and contains no runtime execution callbacks.
