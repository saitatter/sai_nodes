# sai_nodes_core

Pure Dart immutable graph authoring, independent of Flutter and dart:ui.

GraphDocument owns graph spaces. Each space stores nodes, unified control/data/
custom connections, explicit node and connection presentations, frames and
comments. Nested JSON is copied and frozen. Stable node/port/type IDs define
identity; labels and screen position never do.

NodeDefinitionRegistry supplies declarative node descriptions. GraphResolver
tracks the document reads made by dynamic port/field definitions and resolves
bounded fixed points. Missing definitions, removed ports and invalid imported
connections remain in the document with diagnostics.

GraphController executes pure commands and atomic transactions, rolls back
rejected mutations, and owns history/revisions. Selection and camera are ephemeral.
A host document policy can reconcile semantic metadata in the same undo record.
GraphFragment and editing helpers implement clipboard, grouping, alignment,
splicing and duplication; host payloads can carry extra dependencies.
Execution visuals are separate immutable snapshots keyed by scoped entity IDs.

The strict JSON codec supports only version 1. No 0.x decoder or migration exists.
Run dart test in this package. The workspace tool/verify_core_isolation.dart also
copies sources/tests to a temporary standalone Dart package and verifies that no
Flutter dependency is needed.
