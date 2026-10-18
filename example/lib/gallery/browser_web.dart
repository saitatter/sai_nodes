import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('saiGallery.renderShader')
external JSString? _renderShader(web.HTMLCanvasElement canvas, JSString source);
@JS('saiGallery.stopShader')
external void _stopShader(web.HTMLCanvasElement canvas);
@JS('saiGallery.playAudio')
external JSString? _playAudio(
  JSNumber frequency,
  JSNumber gain,
  JSNumber cutoff,
  JSString waveform,
);
@JS('saiGallery.stopAudio')
external void stopDemoAudio();

String initialDemo() =>
    web.window.location.hash.replaceFirst('#', '').split('?').first;
void selectDemoUrl(String id) =>
    web.window.history.replaceState(null, '', '#$id');
void openGalleryLink(String url) {
  web.window.open(url, '_blank', 'noopener,noreferrer');
}

String? playDemoAudio(Map value) => _playAudio(
  (value['frequency'] as num).toJS,
  (value['gain'] as num).toJS,
  (value['cutoff'] as num).toJS,
  (value['waveform'] as String).toJS,
)?.toDart;

class ShaderPreview extends StatefulWidget {
  const ShaderPreview({super.key, required this.source});
  final String source;
  @override
  State<ShaderPreview> createState() => _ShaderPreviewState();
}

class _ShaderPreviewState extends State<ShaderPreview> {
  web.HTMLCanvasElement? canvas;
  String? error;
  void render() {
    if (canvas != null) {
      final problem = _renderShader(canvas!, widget.source.toJS)?.toDart;
      if (mounted) setState(() => error = problem);
    }
  }

  @override
  void didUpdateWidget(ShaderPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) render();
  }

  @override
  void dispose() {
    if (canvas != null) _stopShader(canvas!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: HtmlElementView.fromTagName(
          tagName: 'canvas',
          onElementCreated: (element) {
            canvas = element as web.HTMLCanvasElement;
            canvas!.style.width = '100%';
            canvas!.style.height = '100%';
            canvas!.setAttribute('aria-label', 'Live WebGL material preview');
            render();
          },
        ),
      ),
      if (error != null)
        Positioned.fill(
          child: ColoredBox(
            color: const Color(0xff1c2029),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error!),
              ),
            ),
          ),
        ),
    ],
  );
}
