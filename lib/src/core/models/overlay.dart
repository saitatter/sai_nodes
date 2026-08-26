import 'package:flutter/material.dart';

class OverlayData {
  final Widget child;
  final double? top;
  final double? left;
  final double? bottom;
  final double? right;

  OverlayData({
    required this.child,
    this.top,
    this.left,
    this.bottom,
    this.right,
  });
}
