import 'dart:io';

final _versionLine = RegExp(
  r'^version:[ \t]*(\d+)\.(\d+)\.(\d+)\+(\d+)[ \t]*$',
  multiLine: true,
);

void main(List<String> arguments) {
  try {
    final options = _parseArguments(arguments);
    final bump = options['bump'];
    if (!const {'patch', 'minor', 'major'}.contains(bump)) {
      throw const FormatException('--bump debe ser patch, minor o major.');
    }

    final pubspec = File(options['pubspec'] ?? 'pubspec.yaml');
    if (!pubspec.existsSync()) {
      throw StateError('No existe ${pubspec.path}.');
    }
    final contents = pubspec.readAsStringSync();
    final match = _versionLine.firstMatch(contents);
    if (match == null || _versionLine.allMatches(contents).length != 1) {
      throw const FormatException(
        'pubspec.yaml debe contener una sola versión x.y.z+build.',
      );
    }

    final current = List<int>.generate(
      4,
      (index) => int.parse(match.group(index + 1)!),
    );
    if (current[3] < 1) {
      throw const FormatException('El build actual debe ser mayor que cero.');
    }
    final next = switch (bump) {
      'patch' => <int>[current[0], current[1], current[2] + 1, current[3] + 1],
      'minor' => <int>[current[0], current[1] + 1, 0, current[3] + 1],
      'major' => <int>[current[0] + 1, 0, 0, current[3] + 1],
      _ => throw StateError('Clasificación no soportada: $bump.'),
    };

    final oldVersion = '${current[0]}.${current[1]}.${current[2]}';
    final newVersion = '${next[0]}.${next[1]}.${next[2]}';
    final replacement = 'version: $newVersion+${next[3]}';
    pubspec.writeAsStringSync(contents.replaceFirst(_versionLine, replacement));

    final outputs = <String, String>{
      'release_type': bump!,
      'old_version': oldVersion,
      'old_build': '${current[3]}',
      'version': newVersion,
      'build': '${next[3]}',
    };
    final githubOutput = Platform.environment['GITHUB_OUTPUT'];
    if (githubOutput != null && githubOutput.isNotEmpty) {
      File(githubOutput).writeAsStringSync(
        outputs.entries.map((entry) => '${entry.key}=${entry.value}\n').join(),
        mode: FileMode.append,
      );
    }
    stdout.writeln(
      '$oldVersion+${current[3]} -> $newVersion+${next[3]} ($bump)',
    );
  } on Object catch (error) {
    stderr.writeln('ERROR: $error');
    exitCode = 64;
  }
}

Map<String, String> _parseArguments(List<String> arguments) {
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    if (index + 1 >= arguments.length || !arguments[index].startsWith('--')) {
      throw const FormatException('Los argumentos deben usar --nombre valor.');
    }
    result[arguments[index].substring(2)] = arguments[index + 1];
  }
  if (!result.containsKey('bump')) {
    throw const FormatException('Falta --bump.');
  }
  return result;
}
