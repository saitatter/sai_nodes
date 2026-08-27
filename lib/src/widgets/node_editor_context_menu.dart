import 'dart:math' as math;

import 'package:sai_nodes/src/core/models/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A generic entry in a [NodeEditorContextMenu].
sealed class NodeEditorMenuEntry {
  const NodeEditorMenuEntry();
}

/// A selectable leaf in a [NodeEditorContextMenu].
final class NodeEditorMenuAction extends NodeEditorMenuEntry {
  const NodeEditorMenuAction({
    required this.label,
    this.icon,
    this.onSelected,
    this.enabled = true,
    this.searchText,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onSelected;
  final bool enabled;
  final String? searchText;
}

/// A collapsible group of menu entries.
final class NodeEditorMenuSection extends NodeEditorMenuEntry {
  const NodeEditorMenuSection({
    required this.label,
    required this.entries,
    this.icon,
    this.initiallyExpanded = true,
    this.searchText,
  });

  final String label;
  final List<NodeEditorMenuEntry> entries;
  final IconData? icon;
  final bool initiallyExpanded;
  final String? searchText;
}

/// A visual separator between menu entries.
final class NodeEditorMenuDivider extends NodeEditorMenuEntry {
  const NodeEditorMenuDivider();
}

/// Builds generic editor-menu entries for an empty-canvas position.
typedef NodeEditorMenuBuilder = List<NodeEditorMenuEntry> Function(
  BuildContext context,
  Offset position,
);

/// Builds generic editor-menu entries for a node.
typedef NodeMenuBuilder = List<NodeEditorMenuEntry> Function(
  BuildContext context,
  NodeDataModel node,
);

/// Compatibility alias for the original node-menu builder name.
@Deprecated('Use NodeMenuBuilder instead.')
typedef NodeEditorNodeMenuBuilder = NodeMenuBuilder;

/// Returns menu entries whose labels or search text match [query].
///
/// Section labels match the complete section, while a child match keeps only
/// the matching descendants. Separators at the edge of a filtered list are
/// removed so search results do not begin or end with empty spacing.
List<NodeEditorMenuEntry> filterNodeEditorMenuEntries(
  Iterable<NodeEditorMenuEntry> entries,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return List.unmodifiable(entries);

  final filtered = <NodeEditorMenuEntry>[];
  for (final entry in entries) {
    if (entry is NodeEditorMenuAction) {
      final haystack = '${entry.label} ${entry.searchText ?? ''}'.toLowerCase();
      if (haystack.contains(normalizedQuery)) filtered.add(entry);
    } else if (entry is NodeEditorMenuSection) {
      final sectionHaystack =
          '${entry.label} ${entry.searchText ?? ''}'.toLowerCase();
      if (sectionHaystack.contains(normalizedQuery)) {
        filtered.add(entry);
        continue;
      }

      final children = filterNodeEditorMenuEntries(
        entry.entries,
        normalizedQuery,
      );
      if (children.isNotEmpty) {
        filtered.add(
          NodeEditorMenuSection(
            label: entry.label,
            entries: children,
            icon: entry.icon,
            initiallyExpanded: true,
            searchText: entry.searchText,
          ),
        );
      }
    } else if (entry is NodeEditorMenuDivider) {
      filtered.add(entry);
    }
  }

  while (filtered.isNotEmpty && filtered.first is NodeEditorMenuDivider) {
    filtered.removeAt(0);
  }
  while (filtered.isNotEmpty && filtered.last is NodeEditorMenuDivider) {
    filtered.removeLast();
  }
  return List.unmodifiable(filtered);
}

/// A searchable, collapsible menu for generic node-editor actions.
class NodeEditorContextMenu extends StatefulWidget {
  const NodeEditorContextMenu({
    super.key,
    required this.entries,
    this.searchable = true,
    this.searchHint = 'Search',
    this.closeOnSelect = true,
    this.width = 300,
    this.maxHeight = 480,
  });

  final List<NodeEditorMenuEntry> entries;
  final bool searchable;
  final String searchHint;
  final bool closeOnSelect;
  final double width;
  final double maxHeight;

  @override
  State<NodeEditorContextMenu> createState() => _NodeEditorContextMenuState();
}

class _NodeEditorContextMenuState extends State<NodeEditorContextMenu> {
  final _searchController = TextEditingController();
  final _collapsedSections = <String>{};
  int _highlightedActionIndex = 0;

  @override
  void initState() {
    super.initState();
    _recordInitiallyCollapsed(widget.entries);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _recordInitiallyCollapsed(
    Iterable<NodeEditorMenuEntry> entries, [
    String prefix = '',
  ]) {
    var index = 0;
    for (final entry in entries) {
      if (entry is NodeEditorMenuSection) {
        final path = '$prefix$index';
        if (!entry.initiallyExpanded) _collapsedSections.add(path);
        _recordInitiallyCollapsed(entry.entries, '$path/');
      }
      index++;
    }
  }

  List<NodeEditorMenuEntry> get _visibleEntries =>
      filterNodeEditorMenuEntries(widget.entries, _searchController.text);

  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  void _toggleSection(String path) {
    setState(() {
      if (!_collapsedSections.add(path)) _collapsedSections.remove(path);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _highlightedActionIndex = 0);
  }

  void _select(NodeEditorMenuAction action) {
    if (!action.enabled) return;
    action.onSelected?.call();
    if (widget.closeOnSelect) Navigator.of(context).maybePop();
  }

  List<NodeEditorMenuAction> get _keyboardActions {
    final actions = <NodeEditorMenuAction>[];

    void collect(
      Iterable<NodeEditorMenuEntry> entries,
      String prefix,
    ) {
      var index = 0;
      for (final entry in entries) {
        if (entry is NodeEditorMenuAction) {
          if (entry.enabled) actions.add(entry);
        } else if (entry is NodeEditorMenuSection) {
          final path = '$prefix$index';
          final isCollapsed =
              !_isSearching && _collapsedSections.contains(path);
          if (!isCollapsed) collect(entry.entries, '$path/');
        }
        index++;
      }
    }

    collect(_visibleEntries, '');
    return actions;
  }

  void _activateHighlightedAction() {
    final actions = _keyboardActions;
    if (actions.isEmpty) return;

    final index = _highlightedActionIndex.clamp(0, actions.length - 1).toInt();
    _select(actions[index]);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final actions = _keyboardActions;
    if (actions.isEmpty) return KeyEventResult.ignored;

    var delta = 0;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      delta = 1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      delta = -1;
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      _activateHighlightedAction();
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }

    setState(() {
      _highlightedActionIndex =
          (_highlightedActionIndex + delta) % actions.length;
      if (_highlightedActionIndex < 0) {
        _highlightedActionIndex += actions.length;
      }
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: Focus(
        autofocus: !widget.searchable,
        onKeyEvent: _handleKeyEvent,
        child: SizedBox(
          width: widget.width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.searchable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      onChanged: (_) => setState(() {
                        _highlightedActionIndex = 0;
                      }),
                      onSubmitted: (_) => _activateHighlightedAction(),
                      decoration: InputDecoration(
                        hintText: widget.searchHint,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _isSearching
                            ? IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: _clearSearch,
                              )
                            : null,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(6),
                    child: Builder(
                      builder: (context) {
                        final keyboardActions = _keyboardActions;
                        final highlightedIndex = keyboardActions.isEmpty
                            ? -1
                            : _highlightedActionIndex
                                .clamp(
                                  0,
                                  keyboardActions.length - 1,
                                )
                                .toInt();
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _buildEntries(
                            _visibleEntries,
                            actions: <NodeEditorMenuAction>[],
                            highlightedIndex: highlightedIndex,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildEntries(
    Iterable<NodeEditorMenuEntry> entries, {
    String prefix = '',
    required List<NodeEditorMenuAction> actions,
    required int highlightedIndex,
  }) {
    final widgets = <Widget>[];
    var index = 0;
    for (final entry in entries) {
      final path = '$prefix$index';
      if (entry is NodeEditorMenuAction) {
        final actionIndex = entry.enabled ? actions.length : -1;
        if (entry.enabled) actions.add(entry);
        widgets.add(_buildAction(entry, actionIndex == highlightedIndex));
      } else if (entry is NodeEditorMenuSection) {
        final isCollapsed = !_isSearching && _collapsedSections.contains(path);
        widgets.add(
          _buildSection(
            entry,
            path,
            isCollapsed,
            actions: actions,
            highlightedIndex: highlightedIndex,
          ),
        );
      } else if (entry is NodeEditorMenuDivider) {
        widgets.add(const Divider(height: 8));
      }
      index++;
    }
    return widgets;
  }

  Widget _buildAction(NodeEditorMenuAction action, bool isHighlighted) {
    final foreground = action.enabled
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).disabledColor;
    return Container(
      height: 36,
      decoration: isHighlighted
          ? BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: InkWell(
        onTap: action.enabled ? () => _select(action) : null,
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Icon(action.icon, size: 18, color: foreground),
            ),
            Expanded(
              child: Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    NodeEditorMenuSection section,
    String path,
    bool isCollapsed, {
    required List<NodeEditorMenuAction> actions,
    required int highlightedIndex,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: InkWell(
            onTap: () => _toggleSection(path),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Icon(section.icon, size: 18),
                ),
                Expanded(
                  child: Text(
                    section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(
                  isCollapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        if (!isCollapsed)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildEntries(
                section.entries,
                prefix: '$path/',
                actions: actions,
                highlightedIndex: highlightedIndex,
              ),
            ),
          ),
      ],
    );
  }
}

/// Shows [NodeEditorContextMenu] at a global screen position.
Future<void> showNodeEditorContextMenu(
  BuildContext context, {
  required Offset position,
  required List<NodeEditorMenuEntry> entries,
  bool searchable = true,
  String searchHint = 'Search',
  double width = 300,
  double maxHeight = 480,
}) {
  final screenSize = MediaQuery.sizeOf(context);
  final left = position.dx
      .clamp(8.0, math.max(8.0, screenSize.width - width - 8))
      .toDouble();
  final top = position.dy
      .clamp(8.0, math.max(8.0, screenSize.height - maxHeight - 8))
      .toDouble();

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 100),
    pageBuilder: (context, animation, secondaryAnimation) => Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: NodeEditorContextMenu(
            entries: entries,
            searchable: searchable,
            searchHint: searchHint,
            width: width,
            maxHeight: maxHeight,
          ),
        ),
      ],
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}
