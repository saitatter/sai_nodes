import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'browser.dart';
import 'session.dart';

class DemoPreview extends StatelessWidget {
  const DemoPreview({super.key, required this.session});
  final GallerySession session;
  @override
  Widget build(BuildContext context) {
    final value = session.result?.value;
    if (session.error != null) {
      return _message(
        Icons.error_outline,
        'Something needs a connection',
        session.error!,
        const Color(0xffffa6a6),
      );
    }
    if (value is! Map) {
      return _message(
        Icons.play_circle_outline,
        'Ready when you are',
        'The graph changed. Run it to refresh the result.',
        session.demo.color,
      );
    }
    final accent = session.demo.color;
    switch (session.demo.id) {
      case 'game':
        final jumped = value['jumped'] == true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 156,
              child: LayoutBuilder(
                builder: (context, bounds) => Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Container(
                        height: 1,
                        color: const Color(0xff444354),
                      ),
                    ),
                    TweenAnimationBuilder<double>(
                      key: ValueKey(session.result),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 1600),
                      builder: (context, t, child) => Positioned(
                        left: bounds.maxWidth * .45,
                        bottom:
                            17 +
                            (jumped
                                ? math.sin(t * math.pi) *
                                      math.min(
                                        105,
                                        (value['height'] as num) * 28,
                                      )
                                : 0),
                        child: child!,
                      ),
                      child: Container(
                        width: 30,
                        height: 36,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.face_rounded,
                          color: Color(0xff171520),
                          size: 23,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              jumped ? 'And… lift off.' : 'Staying grounded.',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Velocity ${(value['velocity'] as num).toStringAsFixed(1)} m/s · peak ${(value['height'] as num).toStringAsFixed(2)} m',
            ),
          ],
        );
      case 'workflow':
        return _message(
          value['approved'] == true
              ? Icons.check_circle_outline
              : Icons.pending_actions,
          '${value['route']}',
          '${value['next']}\nA local rule evaluation; no request is sent.',
          accent,
        );
      case 'shader':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 192,
                width: double.infinity,
                child: ShaderPreview(source: value['glsl'] as String),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Live material',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const Text(
              'Generated GLSL · WebGL · animated in real time',
              style: TextStyle(fontSize: 12, color: Color(0xff999eae)),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Generated fragment shader'),
                  content: SizedBox(
                    width: 680,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        value['glsl'] as String,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.code, size: 16),
              label: const Text('View GLSL'),
            ),
          ],
        );
      case 'data':
        final rows = value['rows'] as List;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${value['count']} rows made it through.',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Average score ${(value['average'] as num).toStringAsFixed(1)}',
              style: const TextStyle(color: Color(0xff999eae)),
            ),
            const SizedBox(height: 16),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(width: 66, child: Text('${row['name']}')),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: (row['normalized'] as num)
                            .clamp(0, 1)
                            .toDouble(),
                        color: accent,
                        backgroundColor: const Color(0xff292e3b),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text((row['normalized'] as num).toStringAsFixed(2)),
                  ],
                ),
              ),
            if (rows.isEmpty)
              const Text('No rows match the filter. Lower the minimum score.'),
          ],
        );
      case 'ml':
        final probability = (value['probability'] as num).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${(probability * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 44,
                letterSpacing: -2,
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${value['class']} probability',
              style: const TextStyle(fontSize: 17),
            ),
            const SizedBox(height: 18),
            LinearProgressIndicator(
              value: probability,
              color: accent,
              backgroundColor: const Color(0xff292e3b),
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 16),
            Text(
              'Logit ${(value['logit'] as num).toStringAsFixed(4)}\n2 inputs → 2 hidden units → 1 output',
              style: const TextStyle(color: Color(0xff999eae), height: 1.8),
            ),
            const SizedBox(height: 12),
            const Text(
              'A deterministic forward pass, with editable weights. This example does not train a model.',
              style: TextStyle(fontSize: 12, height: 1.6),
            ),
          ],
        );
      case 'audio':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 100,
              width: double.infinity,
              child: CustomPaint(
                painter: _WavePainter(
                  accent,
                  (value['frequency'] as num).toDouble(),
                  '${value['waveform']}',
                ),
              ),
            ),
            Text(
              '${(value['frequency'] as num).toStringAsFixed(0)} Hz · ${value['waveform']}',
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'Gain ${(value['gain'] as num).toStringAsFixed(2)} · cutoff ${(value['cutoff'] as num).toStringAsFixed(0)} Hz',
            ),
            const SizedBox(height: 12),
            const Text(
              'Use Play patch to hear two seconds of Web Audio. Switching examples or hiding the tab stops playback.',
              style: TextStyle(
                color: Color(0xff999eae),
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ],
        );
      case 'mindmap':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${session.result!.outputs.length} connected ideas',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ..._ideas(value, 0),
          ],
        );
    }
    return const SizedBox.shrink();
  }

  List<Widget> _ideas(Map idea, int depth) => [
    Padding(
      padding: EdgeInsets.only(left: depth * 12.0, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            depth == 0 ? '●  ' : '↳  ',
            style: TextStyle(color: session.demo.color),
          ),
          Expanded(
            child: Text(
              '${idea['label']}',
              style: TextStyle(fontSize: depth == 0 ? 15 : 12, height: 1.4),
            ),
          ),
        ],
      ),
    ),
    for (final child in idea['children'] as List)
      ..._ideas(child as Map, depth + 1),
  ];

  Widget _message(IconData icon, String title, String body, Color color) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 38, color: color),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xffa5a9b7),
              height: 1.7,
              fontSize: 13,
            ),
          ),
        ],
      );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.color, this.frequency, this.waveform);
  final Color color;
  final double frequency;
  final String waveform;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var x = 0.0; x <= size.width; x++) {
      final t =
          x /
          math.max(1, size.width) *
          math.pi *
          2 *
          (frequency / 120).clamp(1, 8);
      final phase = t / (2 * math.pi) % 1;
      final value = switch (waveform) {
        'square' => math.sin(t) >= 0 ? 1.0 : -1.0,
        'triangle' => 1 - 4 * (phase - .5).abs(),
        'sawtooth' => 2 * phase - 1,
        _ => math.sin(t),
      };
      final y = size.height / 2 - value * 27;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.frequency != frequency ||
      oldDelegate.waveform != waveform;
}
