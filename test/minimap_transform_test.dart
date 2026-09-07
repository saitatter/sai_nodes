import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';

void main() {
  for (final bounds in [
    const Rect.fromLTWH(-700, -400, 1200, 600),
    const Rect.fromLTWH(100, 200, 40, 900),
    Rect.zero,
  ]) {
    test('minimap fits and round trips $bounds', () {
      final transform = NodeEditorMinimapTransform(
        bounds: bounds,
        size: const Size(180, 120),
      );
      final fitted = transform.worldRectToMinimap(bounds);
      expect(fitted.left, greaterThanOrEqualTo(11.999));
      expect(fitted.right, lessThanOrEqualTo(168.001));
      expect(fitted.top, greaterThanOrEqualTo(11.999));
      expect(fitted.bottom, lessThanOrEqualTo(108.001));
      const point = Offset(-350, 650);
      expect(
        (transform.minimapToWorld(transform.worldToMinimap(point)) - point)
            .distance,
        lessThan(0.00001),
      );
      expect(transform.worldToMinimap(bounds.center), const Offset(90, 60));
    });
  }
}
