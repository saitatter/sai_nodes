# **SAI Nodes**

## 🚀 **A Fully Customizable Node-Based Editor for Flutter**

**SAI Nodes** is a lightweight, scalable, and highly customizable Flutter package for building interactive, node-based user interfaces.

Whether you're building tools for developers, designers, or end-users, **SAI Nodes** provides the building blocks for:

### 💡 Use Cases

- 🎮 **Visual Scripting Editors** – Game logic, automation flows, or state machines.

- 🛠 **Workflow & Process Designers** – Business rules, decision trees, and automation paths.

- 🎨 **Shader & Material Graphs** – Build custom shaders visually.

- 📊 **Dataflow Tools** – ETL pipelines, AI workflows, or processing graphs.

- 🤖 **ML Architecture Visualizers** – Visualize and configure neural networks.

- 🔊 **Modular Audio Systems** – Synthesizers, effect chains, or sequencing tools.

- 🧠 **Graph-Based UIs** – Mind maps, dependency trees, and hierarchical structures.

---

## 🌟 **Features**

- ✅ **Customizable UI** – Fully override widgets, ports, fields, and layout logic.

- 💾 **Pluggable Storage** – Save/load projects through JSON with full control over serialization.

- ⚡ **Optimized Performance** – Hardware-accelerated rendering, efficient hit testing, and rebuild minimization.

- 🔗 **Flexible Graph System** – Directional edges, typed ports, data links, control links, and more.

- 📏 **Scalable Architecture** – Suitable for lightweight diagrams and complex editors.

- 🌐 **Localization Support** – Easily adapt node-based UIs to multiple languages.

- 🎨 **Lightweight & Elegant** – Minimal dependencies, styling hooks, and a compact public API.

- 🛡️ **Reliable Controller** – Safe project resets, invalid endpoint handling, stale-selection cleanup, and duplicate-link protection.

---

## 🛠 **Roadmap**

The package is being developed as a reusable foundation for workflow, shader, and dataflow editors. Here's what's next:

### ⚙️ **Performance Enhancements**

- **Static Branch Precomputation** – Improve runtime by detecting and collapsing static branches in execution graphs.

### 📚 **Documentation Improvements**

- Expanded API documentation and usage examples.

- Guides for building workflow, shader, audio, and dataflow tools.

### 🎛 **General-Purpose Flexibility**

- 🤖 **Node Configuration State Machine** – Dynamically add or remove ports and fields on nodes at runtime, allowing node structure to adapt to current links and input data.

- 🧑‍🤝‍🧑 **Node Grouping** – Select multiple nodes and group them together for easier organization within complex graphs.

- ♻️ **Reusable Graph Macros** – Define, save, and reuse templates made up of multiple nodes.

- 🎩 **Enhanced Editor Mode** – Add advanced, opt-in editing tools and productivity shortcuts.

---

## 📸 **Screenshots**

<p align="center">
  <img src="https://raw.githubusercontent.com/saitatter/sai_nodes/main/.github/images/node_editor_example.webp" alt="SAI Nodes Example" />
</p>

---

## 📚 **Quickstart Guide**

For a fast start, follow the installation and usage examples below. More complete examples will be added as the editor API grows.

---

## 📦 **Installation**

To add **SAI Nodes** to your Flutter project, include it in your `pubspec.yaml`:

```yaml
dependencies:
  sai_nodes: ^0.1.0
```

Then, run:

```bash
flutter pub get
```

---

## 🛠️ **Usage**

Import the package in your Dart file:

```dart
import 'package:sai_nodes/sai_nodes.dart';
```

Create a controller and add the editor to your widget tree:

```dart
final controller = NodeEditorController();

NodeEditorWidget(
  controller: controller,
  expandToParent: true,
  overlay: () => const <OverlayData>[],
);
```

The editor grid shader must be declared in the consuming application's `pubspec.yaml`:

```yaml
flutter:
  uses-material-design: true
  shaders:
    - packages/sai_nodes/shaders/grid.frag
```

For custom graphs, register `NodePrototype` instances with typed data or control ports and provide field, header, port, node, or context-menu builders as needed.

---

## 🧩 **Examples & Demo**

Explore the repository for the package source, tests, and current integration examples:

- 📄 **[Source repository](https://github.com/saitatter/sai_nodes)**
- 🧪 **[Controller regression tests](https://github.com/saitatter/sai_nodes/tree/main/test)**

---

### 🕹️ **Current Input Support**

**Legend:**

- ✅ Supported
- ❌ Unsupported
- ⚠️ Partial
- 🧪 Untested

| 🖥️ Desktop and 💻 laptop | Windows | Linux | macOS |
| ------------------------ | ------- | ------- | ------- |
| **native/mouse** | ✅ | ✅ | ✅ |
| **native/trackpad** | ✅ | ⚠️ | ✅ |
| **web/mouse** | ✅ | ✅ | ✅ |
| **web/trackpad** | ⚠️ | ⚠️ | ⚠️ |

| 📱 Mobile | Android | iOS |
| ---------- | ------- | ------- |
| **native** | ✅ | 🧪 |
| **web** | ✅ | 🧪 |

---

## 📜 **License**

**SAI Nodes** is open-source and released under the [MIT License](LICENSE).
Contributions are welcome!

---

## 🙌 **Contributing**

We'd love your help in making **SAI Nodes** even better! You can contribute by:

- 💡 Suggesting new features

- 🐛 Reporting bugs

- 🔧 Submitting pull requests

- 👏 Sharing what you've built

Feel free to file an issue or contribute directly on [GitHub](https://github.com/saitatter/sai_nodes).

---

## 🚀 **Let's Build Together!**

Enjoy using **SAI Nodes** and create amazing node-based UIs for your Flutter apps! 🌟
