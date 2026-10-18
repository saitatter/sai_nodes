# The graph playground

Live site: https://saitatter.github.io/sai_nodes/

The site lives entirely in this repository. The Flutter application uses the same
workspace packages as the library example; it does not draw an imitation editor.
The existing minimal example remains at example/lib/main.dart. The gallery starts
at example/lib/gallery_main.dart.

| Example | Link | What the demo host actually does |
| --- | --- | --- |
| Visual scripting | [Jump logic](https://saitatter.github.io/sai_nodes/#game) | Boolean gating and ballistic jump height |
| Workflow & process | [Expense approval](https://saitatter.github.io/sai_nodes/#workflow) | Evaluates the amount against an approval limit |
| Shader & material | [Animated material](https://saitatter.github.io/sai_nodes/#shader) | Generates GLSL from connected nodes; compiles/renders it in WebGL |
| Dataflow & ETL | [Score pipeline](https://saitatter.github.io/sai_nodes/#data) | Filters JSON rows, divides scores by 100, aggregates a report |
| ML architecture | [Tiny classifier](https://saitatter.github.io/sai_nodes/#ml) | Matrix products, biases, ReLU and sigmoid; forward inference only |
| Modular audio | [Synth patch](https://saitatter.github.io/sai_nodes/#audio) | Builds a browser oscillator/gain/low-pass chain and plays two seconds |
| Graph-based UI | [Project map](https://saitatter.github.io/sai_nodes/#mindmap) | Traverses connected ideas and displays the edited hierarchy |

Each example has its own document and undo history for the current tab session.
Drag nodes, connect typed ports, select a node to edit properties, add/delete
nodes, undo/redo, change routing, fit the graph, toggle the minimap or reset.
Source opens editable graph JSON with copy/import. A failed import leaves the
document unchanged. Examples support at most 100 nodes and 200 connections.
Changes are in-memory; copy JSON before closing/reloading if you want to keep them.

On narrow screens, choose an example in the dropdown and open **Preview and
properties** in the toolbar. The same preview/inspector appears in a bottom sheet.
Audio starts only from Play patch and stops on timeout, Stop, example changes,
page hiding or leaving the page. No keys, backend or uploads are required.

## Development

From the repository root:

```sh
flutter pub get
cd example
flutter run -d chrome --target lib/gallery_main.dart
```

Production build from example:

```sh
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --target lib/gallery_main.dart --base-href=/sai_nodes/
```

The build includes CanvasKit resources; loading the editor does not depend on an
external engine CDN. Flutter debug `run` uses its normal development loader.
The graph runtime is in gallery/runtime.dart; browser-only WebGL/Web Audio support
is in web/gallery.js with a conditional Dart bridge. Node definitions remain
declarative. Browser resources are disposed when their preview or patch closes.

## Verification and publishing

Run `flutter test` in example for runtime, widget and minimal-example tests.
Run `npm ci` in tool/browser, then `npx playwright install chromium` there to install
the browser. After building, run `node tool/browser/verify_gallery.mjs` from root.
The test serves the real output under /sai_nodes/ and saves captures/results under
.tmp/gallery-browser. GALLERY_BROWSER may point to an installed Chrome/Edge binary;
GALLERY_URL can instead point at the deployed site for post-deployment checks.
See [the QA inventory](qa.md).

.github/workflows/pages.yml tests the example, builds the web target, exercises it
in Chromium, uploads evidence and deploys the artifact through GitHub Pages.
Pull requests verify the build without deployment. Main pushes and manual runs
on main publish after those checks. Repository Pages must use **GitHub Actions**
as its build source. No generated web files are checked in, and deployments do
not publish new pub.dev package versions or change release tags.
