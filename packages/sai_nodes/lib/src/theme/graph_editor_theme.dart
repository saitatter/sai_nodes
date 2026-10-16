import 'package:flutter/material.dart';

final class GraphEditorTheme {
  const GraphEditorTheme({
    this.background = const Color(0xff15171d),
    this.grid = const Color(0xff30343e),
    this.node = const Color(0xff22252e),
    this.border = const Color(0xff454b5a),
    this.text = const Color(0xffe5e7eb),
    this.selected = const Color(0xffa78bfa),
    this.control = const Color(0xffcbd5e1),
    this.data = const Color(0xff38bdf8),
    this.error = const Color(0xfff87171),
    this.running = const Color(0xff34d399),
    this.frame = const Color(0xff525d79),
    this.connectionWidth = 2,
    this.cornerRadius = 8,
  });
  final Color background,
      grid,
      node,
      border,
      text,
      selected,
      control,
      data,
      error,
      running,
      frame;
  final double connectionWidth, cornerRadius;
}
