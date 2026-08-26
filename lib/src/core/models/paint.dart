import 'dart:ui';

import 'package:sai_nodes/src/styles/styles.dart';

class LinkPaintModel {
  final String id;
  final Offset outPortOffset;
  final Offset inPortOffset;
  final LinkStyle linkStyle;

  LinkPaintModel({
    required this.id,
    required this.outPortOffset,
    required this.inPortOffset,
    required this.linkStyle,
  });
}

class PortPaintModel {
  final (String, String) locator;
  final bool isSelected;
  final Offset offset;
  final PortStyle style;

  PortPaintModel({
    required this.locator,
    required this.isSelected,
    required this.offset,
    required this.style,
  });
}
