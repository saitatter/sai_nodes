import 'package:flutter/material.dart';

import '../models/data.dart';
import '../../styles/styles.dart';

/// The node returned by a world-coordinate graph hit test.
final class NodeHitResult {
  final NodeDataModel node;
  final Rect bounds;

  const NodeHitResult({
    required this.node,
    required this.bounds,
  });

  String get nodeId => node.id;
}

/// The link returned by a world-coordinate graph hit test.
final class LinkHitResult {
  final LinkDataModel link;
  final double distance;
  final LinkCurveType curveType;

  const LinkHitResult({
    required this.link,
    required this.distance,
    required this.curveType,
  });

  String get linkId => link.id;
}
