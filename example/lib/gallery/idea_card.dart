import 'package:flutter/material.dart';
import 'package:sai_nodes/sai_nodes.dart';
import 'inline_field.dart';

/// A relationship card, with the same geometry and anchors as the canvas model.
class IdeaCard extends StatelessWidget {
  const IdeaCard({
    super.key,
    required this.model,
    required this.color,
    required this.isRoot,
    required this.onChanged,
  });
  final GraphNodeViewModel model;
  final Color color;
  final bool isRoot;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: isRoot
          ? Color.alphaBlend(
              color.withValues(alpha: .1),
              const Color(0xff202430),
            )
          : const Color(0xff202430),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: isRoot ? .7 : .3)),
    ),
    child: Padding(
      padding: EdgeInsets.all(model.presentation.collapsed ? 8 : 18),
      child: Row(
        children: [
          Icon(
            isRoot
                ? Icons.lightbulb_outline
                : Icons.chat_bubble_outline_rounded,
            color: color,
            size: model.presentation.collapsed ? 16 : 23,
          ),
          SizedBox(width: model.presentation.collapsed ? 8 : 14),
          Expanded(
            child: model.presentation.collapsed
                ? Text(
                    '${model.node.data['label'] ?? model.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRoot ? 'PROJECT' : 'IDEA',
                        style: TextStyle(
                          color: color,
                          fontSize: 9,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 7),
                      InlineText(
                        key: ValueKey('idea-label-${model.node.id}'),
                        value: '${model.node.data['label'] ?? model.label}',
                        label: 'Idea text',
                        maxLines: 2,
                        onChanged: onChanged,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}
