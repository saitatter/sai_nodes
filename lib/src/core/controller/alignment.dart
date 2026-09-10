import 'package:flutter/foundation.dart';

/// The orientation of a guide shown while nodes are being aligned.
enum AlignmentGuideAxis { vertical, horizontal }

/// A world-space alignment guide.
@immutable
final class AlignmentGuide {
  final AlignmentGuideAxis axis;
  final double position;
  final double from;
  final double to;

  const AlignmentGuide({
    required this.axis,
    required this.position,
    required this.from,
    required this.to,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlignmentGuide &&
          axis == other.axis &&
          position == other.position &&
          from == other.from &&
          to == other.to;

  @override
  int get hashCode => Object.hash(axis, position, from, to);
}

/// The alignment guides calculated for a node drag operation.
final class AlignmentGuideResult {
  final List<AlignmentGuide> guides;

  AlignmentGuideResult(Iterable<AlignmentGuide> guides)
      : guides = List.unmodifiable(guides);

  const AlignmentGuideResult.empty() : guides = const [];

  bool get isEmpty => guides.isEmpty;
  bool get isNotEmpty => guides.isNotEmpty;
}
