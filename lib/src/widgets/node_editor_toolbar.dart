import 'package:flutter/material.dart';

import '../core/controller/core.dart';

class NodeEditorToolbar extends StatelessWidget {
  const NodeEditorToolbar({
    super.key,
    required this.controller,
    this.onAutoLayout,
    this.leading,
    this.trailing,
  });

  final NodeEditorController controller;
  final VoidCallback? onAutoLayout;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([
          controller,
          controller.viewportZoomNotifier,
        ]),
        builder: (context, child) {
          final hasNodes = controller.nodes.isNotEmpty;
          final hasSelection = controller.selectedNodeIds.isNotEmpty;
          final hasHistory = controller.history.canUndo;
          final canRedo = controller.history.canRedo;

          return Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) leading!,
                  _button(
                    tooltip: 'Select all nodes',
                    icon: Icons.select_all,
                    onPressed: hasNodes ? controller.selectAllNodes : null,
                  ),
                  _button(
                    tooltip: 'Fit graph',
                    icon: Icons.fit_screen,
                    onPressed: hasNodes ? controller.focusAllNodes : null,
                  ),
                  _button(
                    tooltip: 'Fit selection',
                    icon: Icons.center_focus_strong,
                    onPressed: hasSelection
                        ? () => controller.focusNodesById(
                              controller.selectedNodeIds,
                            )
                        : null,
                  ),
                  _button(
                    tooltip: 'Reset view',
                    icon: Icons.refresh,
                    onPressed: controller.resetViewport,
                  ),
                  _button(
                    tooltip: 'Zoom out',
                    icon: Icons.remove,
                    onPressed: () => controller.setViewportZoom(-0.1),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${(controller.viewportZoom * 100).round()}%',
                      textAlign: TextAlign.center,
                      semanticsLabel:
                          'Zoom ${(controller.viewportZoom * 100).round()} percent',
                    ),
                  ),
                  _button(
                    tooltip: 'Zoom in',
                    icon: Icons.add,
                    onPressed: () => controller.setViewportZoom(0.1),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: controller.config.enableSnapToGrid
                        ? 'Disable snap to grid'
                        : 'Enable snap to grid',
                    onPressed: () => controller.enableSnapToGrid(
                      !controller.config.enableSnapToGrid,
                    ),
                    icon: Icon(
                      Icons.grid_4x4,
                      color: controller.config.enableSnapToGrid
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  _button(
                    tooltip: 'Auto layout',
                    icon: Icons.account_tree_outlined,
                    onPressed: hasNodes ? onAutoLayout : null,
                  ),
                  PopupMenuButton<NodeAlignment>(
                    tooltip: 'Align selected nodes',
                    enabled: controller.selectedNodeIds.length > 1,
                    icon: const Icon(Icons.align_horizontal_center),
                    onSelected: controller.alignSelectedNodes,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: NodeAlignment.left,
                        child: Text('Align left'),
                      ),
                      PopupMenuItem(
                        value: NodeAlignment.centerHorizontal,
                        child: Text('Align horizontal center'),
                      ),
                      PopupMenuItem(
                        value: NodeAlignment.right,
                        child: Text('Align right'),
                      ),
                      PopupMenuItem(
                        value: NodeAlignment.top,
                        child: Text('Align top'),
                      ),
                      PopupMenuItem(
                        value: NodeAlignment.centerVertical,
                        child: Text('Align vertical center'),
                      ),
                      PopupMenuItem(
                        value: NodeAlignment.bottom,
                        child: Text('Align bottom'),
                      ),
                    ],
                  ),
                  PopupMenuButton<NodeDistributionAxis>(
                    tooltip: 'Distribute selected nodes',
                    enabled: controller.selectedNodeIds.length > 2,
                    icon: const Icon(Icons.space_bar),
                    onSelected: controller.distributeSelectedNodes,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: NodeDistributionAxis.horizontal,
                        child: Text('Distribute horizontally'),
                      ),
                      PopupMenuItem(
                        value: NodeDistributionAxis.vertical,
                        child: Text('Distribute vertically'),
                      ),
                    ],
                  ),
                  _button(
                    tooltip: 'Undo',
                    icon: Icons.undo,
                    onPressed: hasHistory ? controller.history.undo : null,
                  ),
                  _button(
                    tooltip: 'Redo',
                    icon: Icons.redo,
                    onPressed: canRedo ? controller.history.redo : null,
                  ),
                  _button(
                    tooltip: 'Delete selection',
                    icon: Icons.delete_outline,
                    onPressed:
                        hasSelection || controller.selectedLinkIds.isNotEmpty
                            ? controller.deleteSelection
                            : null,
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          );
        },
      );

  static Widget _button({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) =>
      IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onPressed,
      );
}
