import 'dart:io';

/// Runs the core suite outside the Flutter workspace using only the Dart CLI.
Future<void> main() async {
  final repository = File.fromUri(Platform.script).parent.parent;
  final source = Directory('${repository.path}/packages/sai_nodes_core');
  final temporary = await Directory.systemTemp.createTemp('sai-nodes-core-');
  try {
    for (final folder in ['lib', 'test']) {
      final origin = Directory('${source.path}/$folder');
      await for (final file in origin.list(
        recursive: true,
        followLinks: false,
      )) {
        if (file is! File) continue;
        final relative = file.path.substring(source.path.length + 1);
        final target = File('${temporary.path}/$relative');
        await target.parent.create(recursive: true);
        await file.copy(target.path);
      }
    }
    final manifest = await File('${source.path}/pubspec.yaml').readAsString();
    await File('${temporary.path}/pubspec.yaml').writeAsString(
      manifest.replaceFirst(
        RegExp(r'^resolution: workspace\r?\n', multiLine: true),
        '',
      ),
    );
    for (final arguments in [
      ['pub', 'get'],
      ['analyze', '--fatal-infos'],
      ['test', '--reporter', 'expanded'],
    ]) {
      final result = await Process.run(
        Platform.resolvedExecutable,
        arguments,
        workingDirectory: temporary.path,
      );
      stdout.write(result.stdout);
      stderr.write(result.stderr);
      if (result.exitCode != 0) {
        exitCode = result.exitCode;
        return;
      }
    }
    stdout.writeln(
      'Core isolation passed: resolved, analyzed and tested without Flutter.',
    );
  } finally {
    final allowedPrefix =
        '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}sai-nodes-core-';
    if (!temporary.absolute.path.startsWith(allowedPrefix)) {
      throw StateError(
        'Refusing cleanup outside the temporary core test directory.',
      );
    }
    await temporary.delete(recursive: true);
  }
}
