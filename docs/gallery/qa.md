# Gallery QA inventory

The seven examples must use the released immutable graph API and real host
evaluation. They must remain examples, without external services or credentials.

| Surface | Functional check | Visual evidence |
| --- | --- | --- |
| Seven categories | Switch all seven; each graph resolves and evaluates | Desktop capture per category |
| Visual scripting | Change grounded; jump stops; undo restores | Character preview and selected properties |
| Workflow | Amount below/equal/above approval threshold | Approval/review result |
| Shader | Compile/link generated GLSL, change frequency, render pixels | Live material preview |
| Dataflow | Filtering, normalization, empty dataset | Row count and bars |
| Neural network | Matrix/bias/ReLU/sigmoid and invalid shapes | Probability and layer properties |
| Audio | Gesture-started oscillator/gain/filter; timed/manual stop | Patch values; browser audio state |
| Idea map | Rename and connected hierarchy; reject cycle | Expanded idea outline |
| Canvas | Drag/select nodes, connect ports, add/delete, undo/redo, fit | Geometry before/after interaction |
| Editor tools | Routing styles, minimap, reset, editable JSON, copy | Menus, source dialog and invalid JSON |
| Responsive | 1440×960, 1024×768, 390×844, short desktop | No overflow; narrow inspector sheet |
| Navigation | Direct category hash, reload, GitHub/docs links | Correct category after reload |
| Hosting | Production build under /sai_nodes/, self-hosted assets | No browser errors or failed requests |

Off-happy-path checks: missing input/output, incompatible connection, cyclic
hierarchy, malformed source JSON, invalid matrix dimensions and out-of-range audio
gain. Import errors must leave the current document intact. Switching examples
during execution must cancel the old trace and stop audio.

Runtime tests live in example/test/gallery; widget tests cover controls, responsive
layout and source errors. tool/browser/verify_gallery.mjs runs against the actual
release web build using a fresh Chromium profile. Captures/logs belong in .tmp.
