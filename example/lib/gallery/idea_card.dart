import 'package:flutter/material.dart';
import 'package:sai_nodes/sai_nodes.dart';

/// A relationship card, with the same geometry and anchors as the canvas model.
class IdeaCard extends StatelessWidget {
  const IdeaCard({
    super.key,
    required this.model,
    required this.color,
    required this.isRoot,
  });
  final GraphNodeViewModel model;
  final Color color;
  final bool isRoot;

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
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(
            isRoot
                ? Icons.lightbulb_outline
                : Icons.chat_bubble_outline_rounded,
            color: color,
            size: 23,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
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
                Text(
                  '${model.node.data['label'] ?? model.label}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
