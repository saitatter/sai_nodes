# Sai Nodes 1.0 workspace

An immutable graph editing framework with separate Dart and Flutter packages.
The 0.x editor API and its saved formats have been removed. There are no aliases,
legacy decoders or migration helpers.

Stable release: **1.0.0**, requiring Dart 3.12 or later within 3.x. Add `sai_nodes:
^1.0.0` to a Flutter host, or `sai_nodes_core: ^1.0.0` for Dart-only authoring.
See [release notes](docs/releases/1.0.0.md) before upgrading from 0.x.

- [sai_nodes_core](packages/sai_nodes_core): documents, typed definitions,
  dependency-tracked resolution, diagnostics, commands, history and clipboard.
- [sai_nodes](packages/sai_nodes): Flutter canvas, shared geometry, spatial index,
  virtualized node widgets, native frames/comments, routing and execution visuals.
- [example](example): runnable host with dynamic ports and synthetic traces.

A host owns the document controller and application runtime. Node definitions
only describe authoring behavior; execution feedback is supplied separately.
See [architecture](docs/architecture.md), [the implementation plan](docs/greenfield-plan.md)
and [verification/performance notes](docs/greenfield-progress.md).

## Development

```sh
flutter pub get
dart format --output=none --set-exit-if-changed packages benchmark tool example
flutter analyze
(cd packages/sai_nodes_core && dart test)
(cd packages/sai_nodes && flutter test)
(cd example && flutter test)
dart tool/verify_core_isolation.dart
dart run benchmark/core_benchmark.dart
```

Set SAI_NODES_BENCHMARK=1 to run packages/sai_nodes/test/graph_benchmark_test.dart.
Reports are written under .tmp/benchmarks. Widget-test timings measure wall-clock
work and are not GPU frame-rate claims. The example integration suite also runs
on Windows with flutter test integration_test/graph_editor_integration_test.dart -d windows.
