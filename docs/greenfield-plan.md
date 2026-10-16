# Sai Nodes 1.0 + Sai Showrunner Graph System
## Greenfield Rewrite Implementation Plan for Codex

> **Scope:** Full reset. No backward compatibility, no migration support, no legacy API preservation, no old document/schema support.
>
> **Repositories:**
> - `saitatter/sai_nodes`
> - `saitatter/sai-showrunner`
>
> **Primary goal:** Rebuild the graph editing stack around a clean immutable document model, transaction-based mutations, declarative node definitions, dynamic port/field resolution, isolated rendering, and a thin Showrunner integration.
>
> **Non-goals:**
> - Do not preserve `sai_nodes` 0.x public APIs.
> - Do not preserve Showrunner graph JSON formats.
> - Do not build compatibility adapters.
> - Do not migrate old saved automations.
> - Do not retain duplicate graph representations.
> - Do not keep legacy controller/event-bus semantics.
> - Do not move Showrunner runtime execution into the editor package.

---

# 1. Target Architecture

The final architecture should look like this:

```text
                        SAI SHOWRUNNER
                              │
                              ▼
                     AutomationDocument
                              │
                 ┌────────────┴────────────┐
                 │                         │
                 ▼                         ▼
          Editing / Authoring          Runtime
                 │                         │
                 ▼                         ▼
          sai_nodes_core           Graph Compiler / VM
                 │                         │
                 ▼                         ▼
          GraphController          ExecutionTraceService
                 │                         │
                 ▼                         │
           GraphDocument                  │
                 │                         │
                 ▼                         │
             GraphScene                   │
                 │                         │
                 ▼                         ▼
             sai_nodes       ShowrunnerExecutionAdapter
                 │                         │
                 └──────────────┬──────────┘
                                ▼
                          Flutter Canvas
```

Architectural rules:

1. The graph document is the single source of truth.
2. Runtime execution state must never live inside the persisted graph model.
3. Flutter objects must never live inside the core graph model.
4. Node definitions describe graph semantics and editor structure, but do not execute application logic.
5. All persistent mutations go through commands and transactions.
6. Graph connections exist exactly once in the document.
7. Derived indexes are rebuildable caches, never persisted sources of truth.
8. Dynamic ports and fields are resolved by the library, not manually by host applications.
9. Showrunner-specific semantics stay in Showrunner.
10. `sai_nodes` provides editor infrastructure, not broadcaster automation behavior.

---

# 2. Repository Structure

Refactor `sai_nodes` into a workspace with two packages.

```text
sai_nodes/
├── packages/
│   ├── sai_nodes_core/
│   │   ├── lib/
│   │   │   ├── sai_nodes_core.dart
│   │   │   └── src/
│   │   │       ├── model/
│   │   │       ├── geometry/
│   │   │       ├── definitions/
│   │   │       ├── types/
│   │   │       ├── controller/
│   │   │       ├── commands/
│   │   │       ├── transactions/
│   │   │       ├── history/
│   │   │       ├── selection/
│   │   │       ├── resolution/
│   │   │       ├── validation/
│   │   │       ├── indexing/
│   │   │       ├── clipboard/
│   │   │       └── diagnostics/
│   │   └── test/
│   │
│   └── sai_nodes/
│       ├── lib/
│       │   ├── sai_nodes.dart
│       │   └── src/
│       │       ├── editor/
│       │       ├── scene/
│       │       ├── rendering/
│       │       ├── interaction/
│       │       ├── widgets/
│       │       ├── minimap/
│       │       ├── execution/
│       │       ├── theme/
│       │       ├── shortcuts/
│       │       └── platform/
│       └── test/
│
├── example/
├── benchmark/
└── integration_test/
```

`sai_nodes_core` must be usable without importing Flutter widgets or `BuildContext`.

Prefer custom core geometry types instead of `dart:ui`.

---

# 3. Core Graph Model

Delete the existing mutable graph models and replace them completely.

Remove the concepts represented by legacy classes such as:

```text
NodeDataModel
PortDataModel
FieldDataModel
LinkDataModel
NodeEditorProjectDataModel
```

Do not provide compatibility typedefs.

## 3.1 GraphDocument

Create an immutable graph document.

```dart
@immutable
final class GraphDocument {
  const GraphDocument({
    required this.id,
    required this.spaces,
    this.metadata = const {},
  });

  final String id;
  final Map<String, GraphSpace> spaces;
  final Map<String, Object?> metadata;
}
```

## 3.2 GraphSpace

```dart
@immutable
final class GraphSpace {
  const GraphSpace({
    required this.id,
    this.nodes = const {},
    this.connections = const {},
    this.nodePresentations = const {},
    this.connectionPresentations = const {},
    this.frames = const {},
    this.comments = const {},
    this.metadata = const {},
  });

  final String id;
  final Map<String, GraphNode> nodes;
  final Map<String, GraphConnection> connections;
  final Map<String, NodePresentation> nodePresentations;
  final Map<String, ConnectionPresentation> connectionPresentations;
  final Map<String, GraphFrame> frames;
  final Map<String, GraphComment> comments;
  final Map<String, Object?> metadata;
}
```

A space is only an editing container. It does not imply Showrunner subgraph semantics.

## 3.3 GraphNode

```dart
@immutable
final class GraphNode {
  const GraphNode({
    required this.id,
    required this.type,
    this.data = const {},
    this.metadata = const {},
  });

  final String id;
  final String type;
  final Map<String, Object?> data;
  final Map<String, Object?> metadata;
}
```

Rules:

- Node IDs are stable.
- Node IDs are created once.
- IDs are never derived from position.
- IDs are never remapped between the editor and host application.
- `type` references a registered `NodeDefinition`.
- `data` contains semantic configuration.
- `metadata` may contain opaque host-owned information.

## 3.4 NodePresentation

Keep editor-only presentation outside semantic node data.

```dart
@immutable
final class NodePresentation {
  const NodePresentation({
    required this.nodeId,
    required this.position,
    this.size,
    this.title,
    this.collapsed = false,
    this.metadata = const {},
  });

  final String nodeId;
  final GraphPoint position;
  final GraphSize? size;
  final String? title;
  final bool collapsed;
  final Map<String, Object?> metadata;
}
```

Moving or resizing a node must not mutate semantic node data.

## 3.5 GraphConnection

Replace all legacy link ownership logic.

```dart
enum GraphConnectionKind {
  control,
  data,
  custom,
}

@immutable
final class GraphConnection {
  const GraphConnection({
    required this.id,
    required this.from,
    required this.to,
    required this.kind,
    this.data = const {},
  });

  final String id;
  final PortRef from;
  final PortRef to;
  final GraphConnectionKind kind;
  final Map<String, Object?> data;
}
```

```dart
@immutable
final class PortRef {
  const PortRef({
    required this.nodeId,
    required this.portId,
  });

  final String nodeId;
  final String portId;
}
```

Connections exist only in `GraphSpace.connections`.

Do not store connection sets inside ports or nodes.

## 3.6 ConnectionPresentation

```dart
@immutable
final class ConnectionPresentation {
  const ConnectionPresentation({
    required this.connectionId,
    this.waypoints = const [],
    this.label,
    this.labelOffset,
    this.metadata = const {},
  });

  final String connectionId;
  final List<GraphPoint> waypoints;
  final String? label;
  final GraphPoint? labelOffset;
  final Map<String, Object?> metadata;
}
```

## 3.7 Frames

```dart
@immutable
final class GraphFrame {
  const GraphFrame({
    required this.id,
    required this.bounds,
    required this.title,
    this.memberNodeIds = const {},
    this.autoFit = false,
    this.metadata = const {},
  });

  final String id;
  final GraphRect bounds;
  final String title;
  final Set<String> memberNodeIds;
  final bool autoFit;
  final Map<String, Object?> metadata;
}
```

## 3.8 Comments

```dart
@immutable
final class GraphComment {
  const GraphComment({
    required this.id,
    required this.bounds,
    required this.text,
    this.metadata = const {},
  });

  final String id;
  final GraphRect bounds;
  final String text;
  final Map<String, Object?> metadata;
}
```

---

# 4. Graph Indexes

Introduce derived graph indexes.

```text
connectionIdsByNode
connectionIdsByPort
incomingConnectionIds
outgoingConnectionIds
```

Rules:

- Indexes are not serialized.
- Indexes are regenerated from `GraphSpace`.
- Controller mutations update them atomically.
- Add invariant tests comparing incremental indexes against rebuilt indexes.

Also add optional spatial indexes:

```text
NodeSpatialIndex
FrameSpatialIndex
ConnectionBoundsIndex
```

These live outside the persisted model.

---

# 5. Graph Type System

Delete persistence behavior based on Dart generic runtime type identity.

Introduce stable semantic type IDs.

Built-in IDs:

```text
core.any
core.string
core.number
core.boolean
core.object
core.array
```

Showrunner-owned IDs may include:

```text
showrunner.color
showrunner.duration
showrunner.file
showrunner.resource
showrunner.keyboardKey
showrunner.keyCombo
showrunner.obsTransform
showrunner.lightColor
```

Shader graph examples:

```text
shader.float
shader.vec2
shader.vec3
shader.vec4
```

Create a registry/type system that decides whether one output type can connect to an input type.

Rules:

- Exact type matches are valid.
- `core.any` may accept configured compatible types.
- No implicit conversion nodes.
- Showrunner conversion actions remain explicit graph nodes.
- Type IDs are stable strings.
- Dart `Type.toString()` must never participate in persistence or identity.

---

# 6. Port Model

Introduce immutable resolved ports.

```dart
enum GraphPortDirection { input, output }
enum GraphPortKind { control, data }
```

A resolved port should include:

```text
id
direction
kind
dataType
label
maxConnections
metadata
```

Port IDs must be unique within a node regardless of direction.

Do not allow an input and output port to share the same internal ID.

If both need the visible label `Value`, use IDs such as:

```text
value.in
value.out
```

while presenting both as `Value`.

---

# 7. Node Definition System

Replace current prototypes with declarative node definitions.

```dart
abstract interface class NodeDefinition {
  String get type;

  String label(NodeDefinitionContext context);

  NodeStructure resolve(NodeResolutionContext context);

  NodeVisualStyle style(NodeVisualContext context);
}
```

Node definitions must not execute application runtime actions.

A node definition resolves to a `NodeStructure` containing:

```text
ports
fields
constraints
```

Create a dynamic `NodeDefinitionRegistry`.

When a definition changes, affected nodes must be re-resolved.

---

# 8. Dynamic Port and Field Families

Implement first-class declarative resolution.

Create:

```text
StaticPortFamily
DynamicPortFamily
StaticFieldFamily
DynamicFieldFamily
```

A dynamic family receives read-only resolution context containing:

```text
document
space
node
indexes
definitions
```

Required resolver behavior:

1. Resolve initial node structure.
2. Detect structure changes after node data mutation.
3. Preserve ports whose IDs remain stable.
4. Detect invalidated connections.
5. Apply configured invalid-connection policy.
6. Repeat resolution when derived structure affects another dependent structure.
7. Stop after a bounded number of passes.
8. Report non-converging definitions.
9. Produce one transaction result for all derived changes.
10. Never require host code to manually unregister/register prototypes.

---

# 9. Unknown Node Definitions

Support missing definitions natively.

Unknown nodes should retain:

- node ID;
- node type;
- semantic data;
- metadata;
- presentation;
- known persisted connection endpoints.

Render them as clearly unresolved nodes.

Do not delete their data automatically.

This matters for temporarily unavailable Showrunner plugins.

---

# 10. Validation and Diagnostics

Create a generic diagnostics system.

Validate at least:

- missing node definitions;
- missing source/target nodes;
- missing ports;
- wrong port direction;
- type mismatch;
- max connection violations;
- duplicate IDs;
- invalid frame membership;
- invalid presentation references;
- invalid waypoints;
- dynamic resolution errors.

Invalid data must remain representable in the document so the UI can show and repair it.

Do not silently drop invalid connections.

---

# 11. Command-Based Controller

Create a new `GraphController`.

The controller owns:

```text
current GraphDocument
active space
indexes
resolved structures
selection
camera
history
diagnostics
```

Persistent edits happen only through commands.

Implement commands including:

```text
AddNodeCommand
RemoveNodesCommand
UpdateNodeDataCommand
UpdateNodePresentationCommand
MoveNodesCommand
ResizeNodesCommand

AddConnectionCommand
RemoveConnectionsCommand
ReconnectConnectionCommand
UpdateConnectionPresentationCommand

CreateFrameCommand
UpdateFrameCommand
RemoveFrameCommand

CreateCommentCommand
UpdateCommentCommand
RemoveCommentCommand

SetNodeTitleCommand
SetNodeCollapsedCommand
```

Host application code must not directly mutate the document.

---

# 12. Transactions

Create first-class transactions.

```dart
controller.transaction(
  label: 'Insert node into connection',
  (tx) {
    tx.execute(...);
    tx.execute(...);
    tx.execute(...);
  },
);
```

A transaction must be:

- atomic;
- validated before commit;
- resolved before commit;
- represented by one history entry;
- represented by one change notification;
- rollback-safe.

Required compound operations:

```text
spliceNodeIntoConnection
duplicateSelection
deleteSelection
pasteGraphFragment
createFrameFromSelection
moveFrameWithMembers
disconnectNode
replaceNodeType
```

No special-case history implementation should be required for each helper.

---

# 13. History

Replace legacy event replay history.

Use bounded immutable document snapshots + transaction metadata initially.

Requirements:

- configurable history capacity;
- undo;
- redo;
- clear;
- transaction coalescing;
- drag-session coalescing;
- resize-session coalescing;
- no history entries for selection;
- no history entries for camera movement;
- no history entries for execution visuals.

Optimize later using structural sharing if profiling justifies it.

Correctness first.

---

# 14. Selection Model

Selection is ephemeral.

Support:

```text
single select
toggle select
marquee
additive marquee
select all
selection navigation
focus selection
delete selection
```

Selection changes must not dirty the document.

---

# 15. Camera Model

Create a dedicated viewport/camera object.

Controller APIs:

```text
pan
zoomAt
focusBounds
focusNodes
fitSpace
worldToViewport
viewportToWorld
```

Camera state is ephemeral by default.

Allow hosts to persist camera state separately if desired.

---

# 16. Change Notifications

Do not use the existing asynchronous mutation event bus as the document synchronization mechanism.

Expose structured state and document change notifications.

Each committed document mutation should emit a `GraphDocumentChange` containing:

```text
label
revision
GraphChangeSet
```

`GraphChangeSet` should identify:

```text
addedNodeIds
removedNodeIds
updatedNodeIds
addedConnectionIds
removedConnectionIds
updatedConnectionIds
updatedFrameIds
updatedCommentIds
semanticChanged
presentationChanged
```

This change set will later drive selective rendering and runtime cache invalidation.

---

# 17. Clipboard

Implement clipboard around a generic `GraphFragment`.

A fragment contains selected nodes, presentations, internal connections, frames, comments, and optional host payload.

Paste should:

1. decode;
2. allow host enrichment;
3. allocate fresh IDs;
4. offset presentation;
5. commit one transaction.

Provide extension hooks for Showrunner-specific metadata.

---

# 18. Scene Architecture

Add a scene layer between controller state and painting.

`GraphScene` should contain render-ready scene items for:

```text
nodes
connections
frames
comments
viewport
```

The scene builder consumes:

```text
GraphDocument
resolved node structures
geometry
camera
selection
execution visuals
interaction state
```

Do not let painters independently query mutable graph state.

---

# 19. Geometry System

Centralize geometry.

Create:

```text
NodeGeometryEngine
PortGeometryEngine
ConnectionGeometryEngine
FrameGeometryEngine
ViewportTransform
GraphSpatialIndex
```

The same computed geometry must be reused by:

- painting;
- hit testing;
- marquee selection;
- link labels;
- connection routing;
- waypoint interaction;
- minimap;
- auto-scroll;
- execution overlays;
- drop targets.

Avoid duplicate geometry calculations.

---

# 20. Flutter Rendering Architecture

Keep nodes as normal Flutter widgets.

Use custom painting for graph-scale primitives.

Recommended layer stack:

```text
GraphEditor
├── GridLayer
├── FrameLayer
├── ConnectionLayer
├── NodeWidgetLayer
├── PortOverlayLayer
├── SelectionLayer
├── ExecutionLayer
├── InteractionLayer
└── HostOverlayLayer
```

Separate repaint boundaries where useful.

Execution visual updates should repaint execution-related layers without rebuilding all node widgets.

---

# 21. Node Widget API

Create a clean API:

```dart
NodeEditor(
  controller: controller,
  nodeBuilder: ...,
  portBuilder: ...,
  fieldBuilder: ...,
  frameBuilder: ...,
  commentBuilder: ...,
  contextMenuBuilder: ...,
  overlays: ...,
)
```

Builders receive immutable view models.

Do not expose raw mutable internal models.

---

# 22. Rendering Virtualization

Implement viewport-based node widget virtualization.

Goals:

- do not mount thousands of offscreen widgets;
- keep visible nodes mounted;
- use an overscan region;
- keep focused/editing nodes alive;
- keep actively dragged nodes alive;
- preserve text field focus.

Benchmark with and without virtualization.

---

# 23. Connection Rendering

Implement:

```text
straight
bezier
orthogonal
```

Support:

- custom waypoints;
- arrow markers;
- labels;
- hit testing;
- selected state;
- hover state;
- execution state;
- invalid state.

Do not block the release on advanced obstacle-aware routing.

---

# 24. Waypoints

Support:

- double-click connection to add waypoint;
- drag waypoint;
- delete waypoint;
- reset route;
- persistence;
- undo/redo.

Waypoints use world coordinates.

---

# 25. Link Labels

Support both host-defined and derived labels.

Rules:

1. explicit presentation label overrides derived label;
2. derived label updates automatically when source node data changes;
3. labels do not change connection identity;
4. persisted label editing is undoable.

This should replace Showrunner-specific manual `setLinkLabel` maintenance.

---

# 26. Frames

Implement frames natively.

Capabilities:

- create from selection;
- drag;
- resize;
- rename;
- recolor through style/metadata;
- explicit member IDs;
- automatic membership policy;
- optional auto-fit;
- move members with frame;
- select frame;
- delete frame only or frame + members.

Showrunner should no longer need a separate frame persistence adapter.

---

# 27. Comments

Implement comments as native document entities.

Capabilities:

- create;
- edit text;
- resize;
- move;
- selection;
- delete;
- copy/paste;
- undo/redo.

Comments must not be fake nodes.

---

# 28. Minimap

Implement generic minimap support.

Show:

- node bounds;
- frames;
- optional connections;
- viewport rectangle;
- selected nodes;
- optional execution highlights.

Interactions:

- click to recenter;
- drag to pan;
- optional resize;
- optional collapse.

Showrunner may customize styling but should not maintain its own graph geometry implementation.

---

# 29. Auto-Scrolling

Implement viewport edge auto-scroll while:

- dragging nodes;
- dragging selections;
- creating connections;
- dragging waypoints.

Use frame-time-based movement rather than fixed per-event increments.

---

# 30. Drop-to-Create

Implement generic create-on-drop flow.

```text
connection drag
   ↓
host node picker
   ↓
node selection
   ↓
create node
   ↓
resolve ports
   ↓
auto-connect compatible port
   ↓
one transaction
```

The host provides the picker.

`sai_nodes` provides interaction and transaction semantics.

---

# 31. Node Splice

Preserve and redesign the useful splice behavior.

The operation must:

1. inspect original connection;
2. create new node;
3. find compatible input/output ports;
4. replace/reconnect original edge;
5. commit atomically;
6. produce one undo entry.

Allow host override for preferred ports.

---

# 32. Keyboard and Focus Handling

Implement focus-safe editor shortcuts.

Required:

```text
Delete / Backspace
Ctrl/Cmd+C
Ctrl/Cmd+X
Ctrl/Cmd+V
Ctrl/Cmd+D
Ctrl/Cmd+Z
Ctrl/Cmd+Shift+Z
Ctrl/Cmd+A
Ctrl/Cmd+F
Arrow-key selection navigation
```

Do not intercept graph shortcuts while a text input owns the relevant key interaction.

---

# 33. Input Support

Support:

- mouse;
- trackpad;
- touch;
- stylus where Flutter exposes it;
- middle mouse pan;
- space + primary mouse pan;
- pinch zoom;
- configurable scroll zoom.

Create an interaction state machine:

```text
idle
panning
marqueeSelecting
draggingNodes
draggingFrame
resizingNode
creatingConnection
reroutingConnection
draggingWaypoint
editingLabel
```

Avoid overlapping boolean interaction state.

---

# 34. Execution Visualization API

Do not add Showrunner runtime execution to `sai_nodes`.

Add editor-only visualization structures for:

```text
node status
active count
invocation count
duration
error
edge activity
traversal count
metadata
```

Use a scoped node reference:

```text
spaceId + nodeId
```

Execution visualization state must be external to `GraphDocument`.

---

# 35. Execution Replay

Support applying retained execution snapshots to the visualization API.

The editor should not care whether state is:

```text
live
historical
synthetic
test execution
remote execution
```

Expose a listenable/stream-based execution visual source.

---

# 36. Benchmark Suite

Create deterministic benchmark fixtures for:

```text
100 nodes
500 nodes
1,000 nodes
3,000 nodes
5,000 nodes
```

Measure:

- model construction;
- resolver duration;
- index construction;
- initial scene build;
- initial render;
- pan frame time;
- zoom frame time;
- node drag latency;
- marquee selection;
- connection hit testing;
- dynamic port reconciliation;
- undo;
- redo;
- clipboard copy;
- clipboard paste;
- minimap rendering.

Do not claim performance improvements without measurements.

---

# 37. sai_nodes Tests

Minimum suites:

## Core model

- stable IDs;
- immutable semantics;
- duplicate ID rejection;
- connection integrity;
- semantic/presentation separation.

## Types

- compatible/incompatible types;
- wildcard behavior;
- custom host types.

## Definitions

- static structure;
- dynamic ports;
- dynamic fields;
- definition replacement;
- missing definitions;
- non-converging definitions.

## Commands

- every command;
- failure rollback;
- transaction atomicity;
- affected entity sets.

## History

- undo/redo;
- compound transaction;
- drag coalescing;
- redo invalidation.

## Connections

- add/remove/reconnect;
- max connections;
- invalid endpoints/types;
- dynamic invalidation;
- waypoints;
- labels.

## Frames and comments

- CRUD;
- membership;
- resize;
- move;
- auto-fit;
- clipboard;
- undo/redo.

## Interaction

- click selection;
- marquee;
- pan;
- zoom;
- drag;
- connect;
- reroute;
- waypoint drag;
- edge auto-scroll.

## Rendering

- focused node survives virtualization;
- offscreen nodes are not unnecessarily mounted;
- execution updates do not rebuild unrelated nodes.

---

# 38. Showrunner Reset Strategy

Do not retrofit the old `ShowRunnerGraphEditor`.

Create a new graph stack and delete the old one after cutover.

Recommended structure:

```text
packages/showrunner-flutter/lib/graph/
├── domain/
│   ├── automation_document.dart
│   ├── automation_graph.dart
│   ├── graph_scope.dart
│   └── graph_identifiers.dart
│
├── definitions/
│   ├── showrunner_node_definition_provider.dart
│   ├── action_node_definition.dart
│   ├── trigger_node_definition.dart
│   ├── variable_node_definition.dart
│   ├── control_flow_node_definitions.dart
│   └── subgraph_node_definition.dart
│
├── editor/
│   ├── automation_editor_controller.dart
│   ├── automation_editor_session.dart
│   └── graph_workspace.dart
│
├── execution/
│   ├── showrunner_execution_visual_adapter.dart
│   └── execution_selection_controller.dart
│
├── runtime/
│   └── automation_runtime_projection.dart
│
└── presentation/
    ├── showrunner_node_builder.dart
    ├── showrunner_port_builder.dart
    ├── graph_inspector.dart
    ├── graph_toolbar.dart
    └── graph_theme.dart
```

Delete old graph-editor code rather than wrapping it.

---

# 39. New Showrunner Automation Document

Create one new canonical automation document model.

Do not preserve `AutomationData v2`.

Conceptually:

```text
AutomationDocument
├── id
├── GraphDocument
├── subgraph definitions
├── runtime settings
└── metadata
```

Do not create editor-specific duplicate node IDs.

---

# 40. Main Graph and Subgraphs

Represent each editable graph using a `GraphSpace`.

Example:

```text
space:main
space:subgraph:<subgraph-id>
```

Showrunner stores semantic subgraph metadata separately:

```text
id
name
parameters
outputs
entryNodeId
```

Its nodes/connections live in the corresponding graph space.

Navigation should switch active space, not instantiate one controller per subgraph.

---

# 41. Showrunner Node Definition Provider

Build definitions from the existing plugin registry.

Generate definitions for:

```text
Actions
Triggers
Variables
Control-flow nodes
Subgraph calls
Core conversion actions
```

Do not manually call `_ensurePrototype()` style methods.

---

# 42. Action Definitions

For every Showrunner action:

```text
ActionSpec
   │
   ├── configSchema
   │       ↓
   │   input ports / fields
   │
   ├── resultSchema
   │       ↓
   │   output ports
   │
   └── displayName
           ↓
       visual label
```

Decide explicitly which config values are:

```text
connection-capable inputs
inline editable fields
inspector-only fields
```

Do not arbitrarily expose only the first N schema fields.

Add explicit editor hints to plugin/action metadata if necessary.

---

# 43. Trigger Definitions

Triggers are source nodes.

Generate:

- trigger configuration fields;
- event output ports;
- default control-flow output;
- trigger-specific presentation.

Keep trigger subscription config separate from emitted runtime event data.

---

# 44. Variable Definitions

Use stable non-colliding IDs:

```text
value.in
value.out
```

Visible labels may both remain `Value`.

Variables remain Showrunner concepts.

---

# 45. Control Flow Definitions

Create explicit Showrunner definitions for:

```text
if
switch
for
forEach
while
break
continue
return
```

`switch` ports derive from case data.

No manual prototype replacement.

Loops expose explicit control-flow ports plus data as required.

---

# 46. Subgraph Call Definitions

Create a node definition that depends on the referenced subgraph signature.

Input:

```text
exec
parameters...
```

Output:

```text
completed
outputs...
```

When subgraph parameters/outputs change:

```text
signature changes
   ↓
dependency invalidation
   ↓
affected call nodes re-resolve
   ↓
compatible connections retained
   ↓
invalid connections diagnosed
```

No manual controller loops.

---

# 47. Showrunner Type Registry

Bridge `DartDataInputKind` to stable graph type IDs.

Example:

```text
string          -> core.string
number          -> core.number
boolean         -> core.boolean
object          -> core.object
array           -> core.array
duration        -> showrunner.duration
color           -> showrunner.color
filePath        -> showrunner.file
resource        -> showrunner.resource
keyboardKey     -> showrunner.keyboardKey
keyCombo        -> showrunner.keyCombo
obsTransform    -> showrunner.obsTransform
lightColor      -> showrunner.lightColor
```

Keep mapping in one place.

---

# 48. Showrunner Graph Workspace

Rebuild `GraphWorkspace` against the new editor.

Showrunner owns product-specific UI:

```text
graph toolbar
node palette
breadcrumbs
inspector
execution panel
health/diagnostics
plugin-specific configuration
runtime test controls
```

The library owns generic canvas behavior:

```text
selection
pan/zoom
links
frames
minimap
comments
waypoints
clipboard mechanics
history
alignment
drop-to-create interaction
```

Remove duplicated implementations from Showrunner.

---

# 49. Showrunner Inspector

Do not mutate node maps directly.

Inspector changes issue graph commands.

Complex changes use one transaction.

Example:

```text
edit switch cases
   ↓
UpdateNodeDataCommand
   ↓
dynamic resolver
   ↓
connection reconciliation
   ↓
one transaction
```

---

# 50. Showrunner Dirty State

Dirty tracking becomes revision-based.

Track:

```text
lastSavedRevision
currentDocumentRevision
```

Dirty iff they differ.

No queued event workaround.

No `_ignoreQueuedLoadMutations`.

No `_suspendDirtyTracking`.

Ephemeral selection/camera/execution changes do not increment persistent revision.

---

# 51. Showrunner Execution Integration

Keep existing runtime concepts independent:

```text
InterpreterExecutionEngine
CompiledExecutionEngine
DartProductionGraphCompiler
DartGraphVm
ExecutionTraceService
```

The initial integration may add a projection:

```text
AutomationDocument
      ↓
AutomationRuntimeProjection
      ↓
compiler/runtime input
```

The editor does not execute nodes.

---

# 52. Execution Visual Adapter

Create an adapter from Showrunner trace snapshots/events to generic graph execution visuals.

Support:

- live aggregate state;
- pinned execution;
- concurrent executions;
- completed runs;
- aborted runs;
- edge traversal;
- loop iteration metadata;
- subgraph scope;
- invocation counts;
- durations;
- errors.

Map runtime node IDs directly to stable document node IDs.

Do not maintain editor/schema lookup maps.

---

# 53. Runtime Cache Invalidation

Separate semantic and presentation revisions.

Runtime compilation should depend only on semantic graph state.

Must invalidate on:

```text
node config
connection topology
subgraph signature
entry point
```

Must not invalidate on:

```text
position
node size
frame bounds
comment text
connection waypoint
```

---

# 54. New Showrunner Persistence Format

Define a clean new format.

Suggested envelope:

```json
{
  "schemaVersion": 1,
  "id": "automation-...",
  "graph": {
    "spaces": {}
  },
  "subgraphs": {},
  "settings": {},
  "metadata": {}
}
```

Do not preserve legacy:

```text
graph.edges + dataWires split
editorFrames hidden under extra
editorSize hidden in node data
title hidden in node data
schema/editor ID mapping
```

Persist semantic and presentation state explicitly.

---

# 55. Unified Showrunner Connections

Use one connection representation.

Each connection has:

```text
id
kind
from node/port
to node/port
data
```

Runtime compiler branches based on `kind`.

Delete the architectural split between `GraphEdge` and `DataWire`.

---

# 56. Invalid Connections

Persist invalid connections.

They may become invalid because:

- plugin removed;
- port removed;
- subgraph signature changed;
- switch case deleted;
- data type changed.

Do not delete them automatically unless the user explicitly removes them.

Offer repair UX.

---

# 57. Shader Graph Migration

Migrate shader graph editor as the second host of `sai_nodes`.

Use the same:

```text
GraphDocument
GraphSpace
NodeDefinitionRegistry
GraphTypeSystem
GraphController
NodeEditor
```

Shader-specific types:

```text
shader.float
shader.vec2
shader.vec3
shader.vec4
```

The shader compiler consumes semantic graph data, not editor widget models.

Architectural test:

> If the new `sai_nodes` requires Showrunner automation concepts to support shader graphs, the abstraction is wrong.

---

# 58. Delete Legacy Showrunner Graph Code

After cutover, delete or replace:

```text
editor/showrunner_graph_editor.dart
editor/adapter/automation_graph_adapter.dart
editor/persistence/automation_graph_serializer.dart
editor/frames/frame_persistence_adapter.dart
editor/execution/graph_execution_visuals.dart
editor/subgraphs/subgraph_editor_coordinator.dart
```

Do not maintain parallel old/new graph stacks.

---

# 59. Delete Legacy sai_nodes Code

Delete legacy:

```text
NodeDataModel
PortDataModel
FieldDataModel
LinkDataModel
NodeEditorProjectDataModel

legacy runner coupling
legacy project serializer
legacy event replay history
legacy mutable connection ownership
legacy Type-based persistence
legacy prototype classes
legacy load/save API
```

Update exports so only the new API is public.

---

# 60. Recommended Implementation Order

## Phase A — Core foundations

1. Workspace/package split.
2. Core geometry.
3. Immutable graph model.
4. Graph indexes.
5. Stable type system.
6. Diagnostics primitives.

Exit criteria:

- pure Dart tests pass;
- no Flutter dependency in `sai_nodes_core`.

## Phase B — Definitions and resolution

7. Node definitions.
8. Static ports/fields.
9. Dynamic port families.
10. Dynamic field families.
11. Definition registry.
12. Resolver.
13. Unknown definitions.
14. Connection validation.

Exit criteria:

- dynamic switch-style graph tests pass;
- non-convergence detected;
- invalid connections remain representable.

## Phase C — Editing engine

15. Graph commands.
16. Graph transactions.
17. Change sets.
18. History.
19. Selection.
20. Camera.
21. Clipboard fragment model.
22. Generic compound operations.

Exit criteria:

- full graph editing possible without Flutter;
- undo/redo works for all persistent entities.

## Phase D — Flutter scene/rendering

23. Scene builder.
24. Geometry cache.
25. Spatial index.
26. Grid.
27. Node widget layer.
28. Connection painter.
29. Port rendering.
30. Selection layer.
31. Flutter editor shell.

Exit criteria:

- demo supports create/connect/move/delete/undo.

## Phase E — Advanced interaction

32. Connection rerouting.
33. Waypoints.
34. Drop-to-create.
35. Splice.
36. Frames.
37. Comments.
38. Auto-scroll.
39. Alignment guides.
40. Focus-aware shortcuts.
41. Touch/trackpad input.

## Phase F — Performance and tooling

42. Node virtualization.
43. Selective invalidation.
44. Minimap.
45. Benchmarks.
46. Example application.
47. API docs.

## Phase G — Execution visualization

48. Generic visual state.
49. Node execution overlay.
50. Edge execution overlay.
51. Snapshot/replay support.

## Phase H — Showrunner domain reset

52. New AutomationDocument.
53. New unified graph schema.
54. Subgraph model.
55. Runtime projection.
56. New stable identifiers.

## Phase I — Showrunner definitions

57. Type registry bridge.
58. Action definitions.
59. Trigger definitions.
60. Variable definitions.
61. Control-flow definitions.
62. Subgraph call definitions.
63. Core conversion definitions.

## Phase J — Showrunner editor

64. New automation editor controller.
65. New GraphWorkspace.
66. New node renderer.
67. New inspector.
68. Node palette/drop.
69. Subgraph navigation.
70. Diagnostics panel.
71. Save/load new format.
72. Dirty revision logic.

## Phase K — Execution

73. Runtime projection from new document.
74. Compiler compatibility.
75. Interpreter compatibility.
76. Execution trace adapter.
77. Live canvas visualization.
78. Pinned run visualization.
79. Concurrent execution visualization.

## Phase L — Shader graph

80. Shader node definitions.
81. Shader type system.
82. Shader editor UI migration.
83. Shader compiler integration.

## Phase M — Cleanup

84. Delete legacy Showrunner graph stack.
85. Delete legacy `sai_nodes` stack.
86. Remove unused adapters.
87. Remove obsolete tests.
88. Update package dependencies.
89. Re-run benchmarks.
90. Final architecture audit.

---

# 61. Suggested PR Breakdown

## sai_nodes

```text
PR 01  workspace + sai_nodes_core skeleton
PR 02  immutable graph model
PR 03  indexes + type system
PR 04  definition registry
PR 05  dynamic resolver
PR 06  diagnostics + validation
PR 07  commands + transactions
PR 08  history
PR 09  selection + camera
PR 10  clipboard + compound operations
PR 11  scene + geometry
PR 12  base Flutter editor
PR 13  connections + rerouting
PR 14  waypoints + labels
PR 15  frames + comments
PR 16  auto-scroll + alignment + shortcuts
PR 17  minimap
PR 18  virtualization
PR 19  execution visualization
PR 20  benchmarks + example + docs
PR 21  delete legacy implementation
```

## sai-showrunner

```text
PR 01  new automation document model
PR 02  unified connection schema
PR 03  runtime projection
PR 04  Showrunner type bridge
PR 05  action + trigger definitions
PR 06  variables + control flow definitions
PR 07  subgraph definitions
PR 08  new editor controller
PR 09  new GraphWorkspace
PR 10  inspector + palette + node configuration
PR 11  subgraph navigation
PR 12  diagnostics + graph health
PR 13  execution visual adapter
PR 14  runtime/compiler integration
PR 15  shader graph migration
PR 16  delete legacy graph implementation
PR 17  final integration/performance cleanup
```

PR numbering is a planning aid, not a hard serialization constraint.

---

# 62. Codex Implementation Rules

## Rule 1 — No compatibility code

Do not add:

```text
deprecated aliases
legacy constructors
v0.x adapters
old JSON decoders
migration helpers
compatibility typedefs
temporary duplicate public APIs
```

If old code prevents the clean design, delete or replace it.

## Rule 2 — No silent data loss inside the new model

Even though old persisted formats are irrelevant, the new graph engine must preserve invalid or unresolved entities inside a currently loaded new-format document.

## Rule 3 — No Flutter objects in core models

Forbidden inside `sai_nodes_core` models:

```text
BuildContext
GlobalKey
RenderObject
Widget
Offset
Size
Rect
AnimationController
ValueNotifier
```

## Rule 4 — No runtime execution callbacks inside node definitions

Do not add an equivalent of `onExecute` to generic editor node definitions.

## Rule 5 — No duplicated connection ownership

Connections exist only in the graph connection map.

## Rule 6 — Stable IDs everywhere

Never derive identity from:

```text
list index
position
endpoints signature
display name
prototype registration order
```

## Rule 7 — Persistent vs ephemeral separation

Persistent:

```text
nodes
connections
node presentation
connection presentation
frames
comments
semantic metadata
```

Ephemeral:

```text
selection
hover
camera
drag state
focus
execution visuals
context menu state
search UI state
```

## Rule 8 — Transactional persistent mutation

Any user-visible persistent graph mutation must be expressible as one transaction.

## Rule 9 — Host-specific features stay outside core

Showrunner concepts must not leak into `sai_nodes_core`.

## Rule 10 — Tests with every architectural feature

Do not postpone tests until cleanup.

---

# 63. Definition of Done — sai_nodes 1.0

The rewrite is complete when:

- `sai_nodes_core` has no Flutter widget dependency.
- Graph model is immutable.
- Persistent state has one source of truth.
- Connections are stored once.
- IDs are stable.
- Node definitions are declarative.
- Dynamic ports work without host-side prototype replacement.
- Dynamic fields work.
- Type compatibility uses stable IDs.
- Commands and transactions own mutations.
- Undo/redo works across all graph entities.
- Failed mutations rollback atomically.
- Loading/replacement is atomic.
- Selection and camera are ephemeral.
- Frames are native.
- Comments are native.
- Waypoints are native.
- Connection labels are native.
- Minimap is native.
- Edge auto-scroll works.
- Drop-to-create works.
- Splice works.
- Widget focus remains usable.
- Large graph virtualization exists.
- Execution visuals are external to the graph document.
- Benchmarks exist.
- Old `sai_nodes` API has been deleted.

---

# 64. Definition of Done — Sai Showrunner

The Showrunner rewrite is complete when:

- There is one canonical automation document.
- The editor does not maintain separate schema/editor node IDs.
- The editor does not maintain link-signature ID maps.
- Showrunner does not manually rebuild switch prototypes.
- Showrunner does not manually reconcile subgraph call ports.
- There is one graph controller for the complete document.
- Subgraphs use graph spaces.
- Plugin registry data generates node definitions.
- Actions and triggers are generated from existing contracts.
- Runtime execution stays separate from canvas behavior.
- Execution traces map directly to stable node IDs.
- Moving nodes does not invalidate compiled runtime code.
- New persistence cleanly separates semantic and presentation data.
- Shader graph uses the same new graph framework.
- Legacy `ShowRunnerGraphEditor` stack has been deleted.
- Application builds and all new integration tests pass.

---

# 65. Final Architecture Principle

The rewrite should optimize for this rule:

> **Showrunner should describe its graph domain; `sai_nodes` should provide the machinery for editing and visualizing that domain.**

If Showrunner still has to maintain large synchronization maps, manually recreate node prototypes, mirror frame state, infer connection identity from endpoints, or wait for asynchronous editor events to know whether a document changed, the abstraction is still wrong.

Desired end state:

```text
Showrunner plugin/domain definitions
            ↓
ShowrunnerNodeDefinitionProvider
            ↓
sai_nodes GraphController
            ↓
GraphDocument
```

and independently:

```text
GraphDocument
     ↓
Showrunner runtime projection/compiler
     ↓
ExecutionTraceService
     ↓
ShowrunnerExecutionVisualAdapter
     ↓
sai_nodes execution visuals
```

No circular ownership, no duplicate graph models, and no compatibility baggage.
