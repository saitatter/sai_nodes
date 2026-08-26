import 'package:flutter/material.dart';

import 'package:sai_nodes/src/core/models/data.dart';

enum LineDrawMode {
  solid,
  dashed,
  dotted,
}

class GridStyle {
  final double gridSpacingX;
  final double gridSpacingY;
  final double lineWidth;
  final Color lineColor;
  final Color intersectionColor;
  final double intersectionRadius;
  final bool showGrid;

  const GridStyle({
    required this.gridSpacingX,
    required this.gridSpacingY,
    required this.lineWidth,
    required this.lineColor,
    required this.intersectionColor,
    required this.intersectionRadius,
    required this.showGrid,
  });

  const factory GridStyle.basic() = GridStyle._constBasic;

  const GridStyle._constBasic()
      : gridSpacingX = 48.0,
        gridSpacingY = 48.0,
        lineWidth = 0.8,
        lineColor = const Color.fromARGB(80, 120, 144, 156),
        intersectionColor = const Color.fromARGB(120, 144, 164, 174),
        intersectionRadius = 1.5,
        showGrid = true;

  const factory GridStyle.dense() = GridStyle._constDense;

  const GridStyle._constDense()
      : gridSpacingX = 24.0,
        gridSpacingY = 24.0,
        lineWidth = 0.6,
        lineColor = const Color.fromARGB(60, 120, 144, 156),
        intersectionColor = const Color.fromARGB(100, 144, 164, 174),
        intersectionRadius = 1,
        showGrid = true;

  GridStyle copyWith({
    double? gridSpacingX,
    double? gridSpacingY,
    double? lineWidth,
    Color? lineColor,
    Color? intersectionColor,
    double? intersectionRadius,
    bool? showGrid,
  }) {
    return GridStyle(
      gridSpacingX: gridSpacingX ?? this.gridSpacingX,
      gridSpacingY: gridSpacingY ?? this.gridSpacingY,
      lineWidth: lineWidth ?? this.lineWidth,
      lineColor: lineColor ?? this.lineColor,
      intersectionColor: intersectionColor ?? this.intersectionColor,
      intersectionRadius: intersectionRadius ?? this.intersectionRadius,
      showGrid: showGrid ?? this.showGrid,
    );
  }
}

class HighlightAreaStyle {
  final Color color;
  final double borderWidth;
  final Color borderColor;
  final LineDrawMode borderDrawMode;

  const HighlightAreaStyle({
    required this.color,
    required this.borderWidth,
    required this.borderColor,
    required this.borderDrawMode,
  });

  const factory HighlightAreaStyle.basic() = HighlightAreaStyle._constBasic;

  const HighlightAreaStyle._constBasic()
      : color = const Color.fromARGB(30, 41, 121, 255),
        borderWidth = 1.5,
        borderColor = const Color.fromARGB(180, 41, 121, 255),
        borderDrawMode = LineDrawMode.solid;

  HighlightAreaStyle copyWith({
    Color? color,
    double? borderWidth,
    Color? borderColor,
    LineDrawMode? borderDrawMode,
  }) {
    return HighlightAreaStyle(
      color: color ?? this.color,
      borderWidth: borderWidth ?? this.borderWidth,
      borderColor: borderColor ?? this.borderColor,
      borderDrawMode: borderDrawMode ?? this.borderDrawMode,
    );
  }
}

enum LinkCurveType {
  straight,
  bezier,
  ninetyDegree,
}

class LinkStyle {
  final Color? color;
  final LinearGradient? gradient;
  final double lineWidth;
  final LineDrawMode drawMode;
  final LinkCurveType curveType;

  const LinkStyle({
    this.color,
    this.gradient,
    required this.lineWidth,
    required this.drawMode,
    required this.curveType,
  });

  const factory LinkStyle.basic() = LinkStyle._constBasic;

  const LinkStyle._constBasic()
      : color = const Color(0xFF42A5F5),
        lineWidth = 2.5,
        drawMode = LineDrawMode.solid,
        gradient = null,
        curveType = LinkCurveType.bezier;

  const LinkStyle.gradient({
    required this.gradient,
    required this.lineWidth,
    required this.drawMode,
    required this.curveType,
  }) : color = null;

  LinkStyle copyWith({
    Color? color,
    double? lineWidth,
    LineDrawMode? drawMode,
    LinkCurveType? curveType,
  }) {
    return LinkStyle(
      color: color ?? this.color,
      lineWidth: lineWidth ?? this.lineWidth,
      drawMode: drawMode ?? this.drawMode,
      curveType: curveType ?? this.curveType,
    );
  }

  LinkStyle copyWithGradient({
    required LinearGradient gradient,
    double? lineWidth,
    LineDrawMode? drawMode,
    LinkCurveType? curveType,
  }) {
    return LinkStyle.gradient(
      gradient: gradient,
      lineWidth: lineWidth ?? this.lineWidth,
      drawMode: drawMode ?? this.drawMode,
      curveType: curveType ?? this.curveType,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LinkStyle) return false;
    if (gradient != null || other.gradient != null) return false;

    return color == other.color &&
        lineWidth == other.lineWidth &&
        drawMode == other.drawMode &&
        curveType == other.curveType;
  }

  @override
  int get hashCode =>
      color.hashCode ^
      lineWidth.hashCode ^
      drawMode.hashCode ^
      curveType.hashCode;
}

typedef LinkStyleBuilder = LinkStyle Function(LinkState style);

LinkStyle defaultLinkStyleBuilder(LinkState state) =>
    const LinkStyle.basic();

enum PortShape {
  circle,
  triangle,
}

class PortStyle {
  final PortShape shape;
  final Color color;
  final double radius;
  final LinkStyleBuilder linkStyleBuilder;

  const PortStyle({
    required this.shape,
    required this.color,
    required this.radius,
    required this.linkStyleBuilder,
  });

  const factory PortStyle.basic() = PortStyle._constBasic;

  const PortStyle._constBasic()
      : shape = PortShape.circle,
        color = const Color(0xFF42A5F5),
        radius = 5,
        linkStyleBuilder = defaultLinkStyleBuilder;

  PortStyle copyWith({
    PortShape? shape,
    Color? color,
    LinkStyleBuilder? linkStyleBuilder,
    double? radius,
  }) {
    return PortStyle(
      shape: shape ?? this.shape,
      color: color ?? this.color,
      radius: radius ?? this.radius,
      linkStyleBuilder: linkStyleBuilder ?? this.linkStyleBuilder,
    );
  }
}

typedef PortStyleBuilder = PortStyle Function(PortState style);

PortStyle defaultPortStyleBuilder(PortState state) =>
    const PortStyle.basic();

class FieldStyle {
  final BoxDecoration decoration;
  final EdgeInsetsGeometry padding;

  const FieldStyle({
    required this.decoration,
    required this.padding,
  });

  const factory FieldStyle.basic() = FieldStyle._constBasic;

  const FieldStyle._constBasic()
      : decoration = const BoxDecoration(
          color: Color(0xFF37474F),
          borderRadius: BorderRadius.all(Radius.circular(8)),
          border: Border.fromBorderSide(
            BorderSide(
              color: Color(0xFF546E7A),
              width: 1.0,
            ),
          ),
        ),
        padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  FieldStyle copyWith({
    BoxDecoration? decoration,
    EdgeInsetsGeometry? padding,
  }) {
    return FieldStyle(
      decoration: decoration ?? this.decoration,
      padding: padding ?? this.padding,
    );
  }
}

class NodeHeaderStyle {
  final EdgeInsets padding;
  final BoxDecoration decoration;
  final TextStyle textStyle;
  final IconData? icon;

  const NodeHeaderStyle({
    required this.padding,
    required this.decoration,
    required this.textStyle,
    required this.icon,
  });

  const factory NodeHeaderStyle.basic() = NodeHeaderStyle._constBasic;

  const NodeHeaderStyle._constBasic()
      : padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration = const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue,
              Colors.transparent,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
        ),
        textStyle = const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        icon = Icons.expand_more;

  NodeHeaderStyle copyWith({
    EdgeInsets? padding,
    BoxDecoration? decoration,
    TextStyle? textStyle,
    IconData? icon,
  }) {
    return NodeHeaderStyle(
      padding: padding ?? this.padding,
      decoration: decoration ?? this.decoration,
      textStyle: textStyle ?? this.textStyle,
      icon: icon ?? this.icon,
    );
  }
}

typedef NodeHeaderStyleBuilder = NodeHeaderStyle Function(
  NodeState style,
);

NodeHeaderStyle defaultNodeHeaderStyleBuilder(NodeState state) =>
    const NodeHeaderStyle.basic();

class NodeStyle {
  final BoxDecoration decoration;

  const NodeStyle({
    required this.decoration,
  });

  const factory NodeStyle.basic() = NodeStyle._constBasic;

  const NodeStyle._constBasic()
      : decoration = const BoxDecoration(
          color: Color(0xE6263238),
          borderRadius: BorderRadius.all(Radius.circular(12)),
          border: Border.fromBorderSide(
            BorderSide(
              color: Color(0xFF37474F),
              width: 1.5,
            ),
          ),
        );

  const factory NodeStyle.selected() = NodeStyle._constSelected;

  const NodeStyle._constSelected()
      : decoration = const BoxDecoration(
          color: Color(0xE6263238),
          borderRadius: BorderRadius.all(Radius.circular(12)),
          border: Border.fromBorderSide(
            BorderSide(
              color: Color(0xFF42A5F5),
              width: 2.5,
            ),
          ),
        );

  const factory NodeStyle.hovered() = NodeStyle._constHovered;

  const NodeStyle._constHovered()
      : decoration = const BoxDecoration(
          color: Color(0xE6263238),
          borderRadius: BorderRadius.all(Radius.circular(12)),
          border: Border.fromBorderSide(
            BorderSide(
              color: Color(0xFF64B5F6),
              width: 2.0,
            ),
          ),
        );

  NodeStyle copyWith({
    BoxDecoration? decoration,
  }) {
    return NodeStyle(
      decoration: decoration ?? this.decoration,
    );
  }
}

typedef NodeStyleBuilder = NodeStyle Function(NodeState style);

NodeStyle defaultNodeStyleBuilder(NodeState state) {
  return state.isSelected
      ? const NodeStyle.selected()
      : state.isHovered
          ? const NodeStyle.hovered()
          : const NodeStyle.basic();
}

class NodeEditorStyle {
  final BoxDecoration decoration;
  final EdgeInsetsGeometry padding;
  final GridStyle gridStyle;
  final HighlightAreaStyle highlightAreaStyle;

  const NodeEditorStyle({
    this.decoration = const BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color(0xFF1A1A1A),
          Color(0xFF0D1117),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    this.padding = const EdgeInsets.all(0.0),
    this.gridStyle = const GridStyle.basic(),
    this.highlightAreaStyle = const HighlightAreaStyle.basic(),
  });

  NodeEditorStyle copyWith({
    BoxDecoration? decoration,
    EdgeInsetsGeometry? padding,
    GridStyle? gridStyle,
    HighlightAreaStyle? highlightAreaStyle,
  }) {
    return NodeEditorStyle(
      decoration: decoration ?? this.decoration,
      padding: padding ?? this.padding,
      gridStyle: gridStyle ?? this.gridStyle,
      highlightAreaStyle: highlightAreaStyle ?? this.highlightAreaStyle,
    );
  }
}
