# Local performance checkpoint

Windows, Flutter 3.47.7 / Dart 3.13.5. Five samples per size, including cold
startup/JIT work. Other verification processes were active during measurement.
Values are wall-clock milliseconds; p95 is the observed upper sample at this
sample count. These are diagnostic measurements, not frame-rate guarantees.

## Core operations (median / p95 ms)

| Nodes | Resolve | Move | Clipboard paste |
| ---: | ---: | ---: | ---: |
| 100 | 2.1 / 21.9 | 2.7 / 7.9 | 5.1 / 12.2 |
| 500 | 6.0 / 8.0 | 14.4 / 16.8 | 25.2 / 34.9 |
| 1000 | 13.4 / 16.6 | 36.4 / 42.1 | 52.6 / 63.1 |
| 3000 | 53.2 / 55.9 | 105.5 / 131.0 | 194.3 / 221.6 |
| 5000 | 99.3 / 103.2 | 209.0 / 236.8 | 373.5 / 424.1 |

## Flutter widget-test operations (median / p95 ms)

| Nodes | Initial render | Pan frame | Zoom frame | Move and repaint |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 39.7 / 266.0 | 10.2 / 18.9 | 8.4 / 10.9 | 19.2 / 23.8 |
| 500 | 69.5 / 72.8 | 12.8 / 20.7 | 11.8 / 14.5 | 37.6 / 43.1 |
| 1000 | 64.7 / 100.2 | 16.7 / 21.0 | 9.3 / 11.3 | 54.1 / 75.6 |
| 3000 | 82.5 / 93.2 | 26.8 / 27.5 | 7.5 / 12.6 | 149.1 / 208.4 |
| 5000 | 76.4 / 118.4 | 27.8 / 46.2 | 6.5 / 12.1 | 271.9 / 348.7 |

Node mounting is virtualized and offscreen nodes are not built. Semantic edits
still copy immutable maps, rebuild indexes and resolve document diagnostics;
large edits exceed a frame budget. Optimization should target those costs if
sustained 60-fps dragging on several thousand nodes becomes a product requirement.
Execution updates use a separate painter and do not rebuild node contents.

Reproduce with dart run benchmark/core_benchmark.dart, and with
SAI_NODES_BENCHMARK=1 flutter test test/graph_benchmark_test.dart inside the Flutter
package. Full samples are written to ignored .tmp/benchmarks/core.json and
.tmp/benchmarks/flutter.json at repository root.
