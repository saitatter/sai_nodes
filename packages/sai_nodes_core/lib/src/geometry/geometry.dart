import 'dart:math' as math;

final class GraphPoint {
  const GraphPoint(this.x, this.y);
  static const zero = GraphPoint(0, 0);
  final double x;
  final double y;
  bool get isFinite => x.isFinite && y.isFinite;
  GraphPoint operator +(GraphPoint other) =>
      GraphPoint(x + other.x, y + other.y);
  GraphPoint operator -(GraphPoint other) =>
      GraphPoint(x - other.x, y - other.y);
  GraphPoint scale(double factor) => GraphPoint(x * factor, y * factor);
  double distanceTo(GraphPoint other) =>
      math.sqrt(math.pow(x - other.x, 2) + math.pow(y - other.y, 2));
  @override
  bool operator ==(Object other) =>
      other is GraphPoint && x == other.x && y == other.y;
  @override
  int get hashCode => Object.hash(x, y);
}

final class GraphSize {
  const GraphSize(this.width, this.height);
  final double width;
  final double height;
  bool get isValid =>
      width.isFinite && height.isFinite && width >= 0 && height >= 0;
  @override
  bool operator ==(Object other) =>
      other is GraphSize && width == other.width && height == other.height;
  @override
  int get hashCode => Object.hash(width, height);
}

final class GraphRect {
  const GraphRect(this.left, this.top, this.width, this.height);
  factory GraphRect.fromPoints(GraphPoint first, GraphPoint second) =>
      GraphRect(
        math.min(first.x, second.x),
        math.min(first.y, second.y),
        (second.x - first.x).abs(),
        (second.y - first.y).abs(),
      );
  final double left;
  final double top;
  final double width;
  final double height;
  double get right => left + width;
  double get bottom => top + height;
  GraphPoint get center => GraphPoint(left + width / 2, top + height / 2);
  bool get isValid =>
      left.isFinite &&
      top.isFinite &&
      right.isFinite &&
      bottom.isFinite &&
      GraphSize(width, height).isValid;
  bool contains(GraphPoint point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= top &&
      point.y <= bottom;
  bool overlaps(GraphRect other) =>
      left <= other.right &&
      right >= other.left &&
      top <= other.bottom &&
      bottom >= other.top;
  GraphRect translate(GraphPoint delta) =>
      GraphRect(left + delta.x, top + delta.y, width, height);
  GraphRect inflate(double amount) => GraphRect(
    left - amount,
    top - amount,
    width + 2 * amount,
    height + 2 * amount,
  );
  GraphRect union(GraphRect other) => GraphRect.fromPoints(
    GraphPoint(math.min(left, other.left), math.min(top, other.top)),
    GraphPoint(math.max(right, other.right), math.max(bottom, other.bottom)),
  );
  @override
  bool operator ==(Object other) =>
      other is GraphRect &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height;
  @override
  int get hashCode => Object.hash(left, top, width, height);
}
