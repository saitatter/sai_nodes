# Immutable graph integration

## Ownership

The host owns one GraphController for a complete document, including subgraph
spaces. GraphDocument is the only persistent authoring state. Runtime programs,
indexes, geometry, search, camera, selection, hover and execution feedback are
rebuildable projections or ephemeral state. They are never serialized as nodes.

The Flutter NodeEditor reads its controller and a GraphScene. NodeGeometryEngine
is the authority for positions, bounds and ports in rendering, hit testing,
connections, selection, minimap and host focus/fit operations.

## Definitions and types

Definitions describe labels, styles, port families, field families and constraints.
Dynamic families read through NodeResolutionContext; dependencies invalidate only
structures that actually read changed state. Resolution has a convergence limit.
Registry.replaceAll validates the whole replacement before one publication.

Resolved ports have stable IDs, directions, kinds, capacities and semantic type
IDs. Compatibility is exact unless a target explicitly accepts another source
or the configured any policy permits it. No implicit conversion is inserted.
Field data paths are stable semantic keys; labels are presentation. Set the
placement metadata to inspector for fields that should not consume inline rows.

## Mutation and persistence

Commands are pure document transforms. A transaction applies all commands,
runs the host document policy, resolves and validates, then publishes one history
entry. Failure leaves document, revision and history unchanged. Undo/redo restores
all authoring entities and metadata. Selection/camera are clamped when spaces or
entities disappear. Replacing a document is atomic and resets history.

Save a captured document/revision, then call markSaved(revision: capturedRevision)
after the write finishes. New unsaved resources use markUnsaved. This preserves
edits made during asynchronous saving and correctly handles save points after undo.
The strict version-1 codec rejects unknown schema fields and retains malformed
semantic references for diagnostics; loading never silently repairs topology.

## Clipboard and execution

GraphFragment captures selected nodes, internal connections, selected frames and
comments. Paste reserves IDs across all document spaces, remaps entities and
commits one transaction. transformRemapped can rewrite host semantic references;
prepareTransaction adds host dependencies atomically. NodeEditor captureFragment
and pasteFragment hooks cover native shortcuts, context menus and duplication.
Hosts should preserve literal JSON while rewriting only real semantic references.
Clipboard completions are ignored if controller or active space changed.

The host compiler/runtime consumes the document independently. Definitions carry
no execution callbacks. GraphExecutionVisualSource provides scoped snapshots with
status, activity counts, traversal counts, errors, duration and metadata. Animation
uses separate repaint listeners; feedback does not dirty authoring or remount node
content. A host may aggregate concurrent runs, pin a run or show retained history.

## Verification and limits

Core tests cover strict persistence, immutable ownership, randomized index parity,
dynamic dependency invalidation, rollback and history across graph entities.
Flutter tests exercise actual pointer/keyboard/context-menu flows and compare
geometry, virtualization and repaint behavior. The example reuses these on native
Windows. Benchmarks record median/p95 work at 100, 500, 1000, 3000 and 5000 nodes.

Virtualization reduces mounted widgets; a whole immutable edit still copies maps
and resolves graph diagnostics. Large compound operations can exceed a frame
budget. Benchmark reports are evidence of those costs, not a 60-fps guarantee.
