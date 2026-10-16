# Greenfield rewrite progress

Updated 2026-10-16 on local branch `rewrite/graph-1.0`.

The complete source plan is preserved in [greenfield-plan.md](greenfield-plan.md).
This is the start of the rewrite, not the completed 1.0 editor.

## Phase A — core foundations

Implemented:

- Workspace with `packages/sai_nodes_core` and `packages/sai_nodes`.
- Custom world-coordinate point, size and rectangle types, without `dart:ui`.
- Immutable documents/spaces, nodes, unified connections and endpoints,
  presentations, frames and comments. Collections and nested semantic/metadata
  JSON are copied and frozen; snapshot equality is structural.
- New version-1 codec. All entities and opaque host metadata round-trip.
  Unknown node types and dangling connection endpoints remain representable.
  Unsupported versions and fields fail explicitly; no old-format decoder exists.
- Derived adjacency indexes by node/port and direction. Incremental updates are
  compared with full rebuilds and independent scans across 120 deterministic
  graph edits, including parallel links, self-links and reconnection. Caches are
  immutable snapshots and are never serialized.
- Stable semantic type IDs, core types, directional host compatibility and
  configurable `core.any` acceptance. No implicit conversion nodes.
- Diagnostic primitives and structural validation for IDs, endpoint references,
  presentations, geometry and frame membership. Validation does not repair or
  delete invalid entities. Definition/port/type validation follows in Phase B.
- CI package test paths and publishing manifest paths updated for the workspace.
  Separate Dart-only isolation job. No package or tag was published.

The existing Flutter canvas sources, shader and behavioral tests were relocated
into `packages/sai_nodes`. This is a repository move, not a compatibility adapter
or a second new document representation. The canvas still uses the old controller
until the replacement editing/scene stack is implemented; it is not presented as
the final 1.0 API. Small analyzer corrections accommodate the new SDK floor.

Verification:

- Core: 11 pure Dart tests passed, including deep immutability, full persistence,
  semantic/presentation separation, invalid-reference retention and index invariants.
- Standalone isolation: copied core package resolves, analyzes and passes the
  same tests without Flutter or workspace resolution.
- Existing Flutter canvas: 75 tests passed after relocation. The generated
  arithmetic-only sample test was removed because it tested no editor behavior.
- Workspace analysis: no issues.
- Formatting checked for all package and tooling Dart sources.

## Phase B — definitions and resolution

Implemented the definition registry, immutable resolved ports and fields, static
and dynamic families, bounded fixed-point resolution, missing definitions,
registry invalidation and connection validation. Invalid connections stay in the
document by default; removal is an explicit policy. Tests cover switch-style
ports/fields, dependent passes, non-convergence, replacement, capacity and direction.

## Phase C — editing engine

Implemented pure commands for nodes, connections, spaces, frames, comments and
presentation; atomic transactions with rollback; synchronous document changes and
indexes; bounded snapshot history with coalescing; saved revision tracking;
semantic/presentation revision separation; ephemeral selection/camera; typed
clipboard fragments and compound paste, duplication, deletion, frame movement,
disconnect and splice operations. Tests cover rollback, undo/redo, saved barriers,
new IDs and failure atomicity. Core suite: 29 tests at this checkpoint.

## Phases D/E — scene and interaction

Implemented the new `NodeEditor` shell, immutable scene/view models, shared node
and connection geometry, spatial indexes, grid, widget nodes, port overlay,
straight/Bezier/orthogonal routes, arrows, labels, invalid edge styling, hover,
selection, pan/zoom, touch pinch and trackpad events. Generic canvas behavior
includes node movement/resizing, marquee, rerouting with stable edge IDs,
waypoints, drop-to-create, context splice, frames/comments, auto-fit/containment,
alignment helpers, focus-aware shortcuts and elapsed-time edge auto-scroll.

Virtualization retains focused and dragged nodes. Cached widget contents and
geometry avoid rebuilding unrelated nodes on camera or execution changes.
The example supports Windows/web, JSON round-trip and synthetic execution replay.

Checkpoint: 89 Flutter package tests passed (one opt-in benchmark skipped),
31 pure Dart core tests passed, example test passed, and native Windows editor
integration passed. The native target also imports the geometry/spatial tests.

## Phase F — performance and tooling

Deterministic benchmarks cover 100/500/1,000/3,000/5,000 nodes with five samples,
median and p95 for core mutations/history/clipboard/resolution and Flutter scene,
visible mounting, pan/zoom, drag updates, hit testing and minimap. Run
`dart benchmark/core_benchmark.dart`, then opt into `graph_benchmark_test.dart`
with `SAI_NODES_BENCHMARK=1`. Generated JSON is in `.tmp/benchmarks`.

Measurements exposed an O(N²) copy of the previous structure map per context;
contexts now use read-only views. Access-tracked dependencies support safe
resolution reuse and are checked against fresh resolution in tests. Clipboard
paste performs a bulk merge instead of copying growing graph maps per entity.
Connection geometry is cached too. These are measured local improvements, not
a claim that 5,000-node editing meets a production frame-time target; that case
still has noticeable document-update latency. Widget-test wall-clock timings are
not production GPU timings. API usage is documented in `docs/api.md`.

## Phase G — execution visuals

Generic scoped node/connection references and immutable snapshots support live,
retained, synthetic and remote sources without executing nodes. Counts, status,
duration, errors and animated traversals live outside the graph document. A
separate repaint source updates execution layers; tests verify no node content
rebuild and no document dirtying from visual updates.

Next: Showrunner domain reset and integration (Phases H onward).

## Showrunner integration

Showrunner still uses its pinned Git dependency and current graph format. No
local override, saved document conversion or dual persistence was introduced.
The domain reset starts in Phase H, after the core/editor foundation is ready.
Automation and shader compiler execution remain Showrunner-owned.
