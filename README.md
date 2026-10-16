# Sai Nodes workspace

This repository is being rewritten for Sai Nodes 1.0 on `rewrite/graph-1.0`.
The canonical implementation plan is [docs/greenfield-plan.md](docs/greenfield-plan.md).
See [progress and verification](docs/greenfield-progress.md) for completed phases.

- `packages/sai_nodes_core`: immutable documents, geometry, indexes, stable type
  IDs and diagnostics. Pure Dart, independently testable without Flutter.
- `packages/sai_nodes`: Flutter canvas package, relocated from the repository
  root. Its controller/scene cutover to the new core is a subsequent phase.

The target architecture has one persisted graph document, transaction-owned
mutations and host-provided declarative definitions. Application runtime
execution stays outside the editor. Version 1.0 will replace the 0.x API and
saved formats without compatibility adapters or migration support.

## Development

```sh
flutter pub get
dart format --output=none --set-exit-if-changed packages tool
flutter analyze
(cd packages/sai_nodes_core && dart test)
(cd packages/sai_nodes && flutter test)
dart tool/verify_core_isolation.dart
```

The isolation tool copies only core sources/tests into a temporary directory,
resolves them with the Dart CLI, runs analysis and tests, then removes its own
copy. Its only manifest adjustment is removing workspace resolution.

No Showrunner dependency has been changed yet. Its cutover follows the core,
editing engine and Flutter scene phases.
