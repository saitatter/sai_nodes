import 'package:sai_nodes/src/core/controller/core.dart';
import 'package:sai_nodes/src/core/controller/navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NodeEditorShortcutsWidget extends StatelessWidget {
  final NodeEditorController controller;
  final Widget child;
  final Future<void> Function(BuildContext context)? onCopy;
  final Future<void> Function(BuildContext context)? onPaste;
  final Future<void> Function(BuildContext context)? onCut;
  final VoidCallback? onDuplicate;
  final void Function(LogicalKeyboardKey key, {required bool extendSelection})?
      onMoveSelection;

  const NodeEditorShortcutsWidget({
    super.key,
    required this.controller,
    required this.child,
    this.onCopy,
    this.onPaste,
    this.onCut,
    this.onDuplicate,
    this.onMoveSelection,
  });

  @override
  Widget build(BuildContext context) {
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    void navigate(LogicalKeyboardKey key, bool extend) {
      if (onMoveSelection != null) {
        onMoveSelection!(key, extendSelection: extend);
        return;
      }
      controller.navigateSelection(
        switch (key) {
          LogicalKeyboardKey.arrowLeft => NodeNavigationDirection.left,
          LogicalKeyboardKey.arrowRight => NodeNavigationDirection.right,
          LogicalKeyboardKey.arrowUp => NodeNavigationDirection.up,
          _ => NodeNavigationDirection.down,
        },
        extendSelection: extend,
      );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF):
            controller.focusAllNodes,
        SingleActivator(
          LogicalKeyboardKey.equal,
          control: !isMacOS,
          meta: isMacOS,
        ): () => controller.setViewportZoom(0.1),
        SingleActivator(
          LogicalKeyboardKey.minus,
          control: !isMacOS,
          meta: isMacOS,
        ): () => controller.setViewportZoom(-0.1),
        SingleActivator(
          LogicalKeyboardKey.digit0,
          control: !isMacOS,
          meta: isMacOS,
        ): controller.resetViewport,
        SingleActivator(
          LogicalKeyboardKey.keyA,
          control: !isMacOS,
          meta: isMacOS,
        ): () => controller.selectAllNodes(),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            controller.clearSelection(),
        const SingleActivator(LogicalKeyboardKey.delete): () {
          controller.deleteSelection();
        },
        const SingleActivator(LogicalKeyboardKey.backspace): () {
          controller.deleteSelection();
        },
        SingleActivator(
          LogicalKeyboardKey.keyC,
          control: !isMacOS,
          meta: isMacOS,
        ): () =>
            onCopy?.call(context) ??
            controller.clipboard.copySelection(context: context),
        SingleActivator(
          LogicalKeyboardKey.keyV,
          control: !isMacOS,
          meta: isMacOS,
        ): () =>
            onPaste?.call(context) ??
            controller.clipboard.pasteSelection(context: context),
        SingleActivator(
          LogicalKeyboardKey.keyX,
          control: !isMacOS,
          meta: isMacOS,
        ): () =>
            onCut?.call(context) ??
            controller.clipboard.cutSelection(context: context),
        SingleActivator(
          LogicalKeyboardKey.keyD,
          control: !isMacOS,
          meta: isMacOS,
        ): () => onDuplicate?.call(),
        for (final key in const [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
        ])
          SingleActivator(key): () => navigate(key, false),
        for (final key in const [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
        ])
          SingleActivator(
            key,
            shift: true,
          ): () => navigate(key, true),
        SingleActivator(
          LogicalKeyboardKey.keyS,
          control: !isMacOS,
          meta: isMacOS,
        ): () => controller.project.save(context: context),
        SingleActivator(
          LogicalKeyboardKey.keyO,
          control: !isMacOS,
          meta: isMacOS,
        ): () => controller.project.load(context: context),
        SingleActivator(
          LogicalKeyboardKey.keyN,
          control: !isMacOS,
          meta: isMacOS,
          shift: true,
        ): () => controller.project.create(context: context),
        SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: !isMacOS,
          meta: isMacOS,
        ): () => controller.history.undo(),
        SingleActivator(
          LogicalKeyboardKey.keyY,
          control: !isMacOS,
          meta: isMacOS,
        ): () => controller.history.redo(),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
