import 'package:flutter/material.dart';

String initialDemo() => 'game';
void selectDemoUrl(String id) {}
void openGalleryLink(String url) {}
String? playDemoAudio(Map value) =>
    'Audio playback is available in the web gallery.';
void stopDemoAudio() {}

class ShaderPreview extends StatelessWidget {
  const ShaderPreview({super.key, required this.source});
  final String source;
  @override
  Widget build(BuildContext context) => const Center(
    child: Text('WebGL preview is available in the web gallery.'),
  );
}
