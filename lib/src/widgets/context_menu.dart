import 'package:flutter/material.dart';

import 'package:flutter_context_menu/flutter_context_menu.dart';

bool isContextMenuVisible = false;

void createAndShowContextMenu(
  BuildContext context, {
  required List<ContextMenuEntry<dynamic>> entries,
  required Offset position,
  ValueChanged<Object?>? onDismiss,
}) async {
  if (isContextMenuVisible) return;

  isContextMenuVisible = true;

  final menu = ContextMenu<dynamic>(
    entries: entries,
    position: position,
    padding: const EdgeInsets.all(8),
  );

  final copiedValue = await showContextMenu<dynamic>(
    context,
    contextMenu: menu,
  ).then((value) {
    isContextMenuVisible = false;
    return value;
  });

  if (onDismiss != null) onDismiss(copiedValue);
}
