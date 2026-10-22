import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const manifestKeys = <String>{
  'version',
  'buildNumber',
  'minimumSupportedVersion',
  'mandatory',
  'title',
  'description',
  'apkFile',
  'sha256',
  'publishedAt',
};

final _versionPattern = RegExp(r'^\d+(?:\.\d+){1,3}(?:[-+][0-9A-Za-z.-]+)?$');
final _apkNamePattern = RegExp(r'^[0-9A-Za-z][0-9A-Za-z._-]{0,119}\.apk$');

class PubspecReleaseVersion {
  const PubspecReleaseVersion(this.version, this.buildNumber);

  final String version;
  final int buildNumber;
}

PubspecReleaseVersion parsePubspecVersion(String contents) {
  final match = RegExp(
    r'^version:\s*([^\s+]+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(contents);
  if (match == null) {
    throw const FormatException(
      'pubspec.yaml debe declarar version con el formato x.y.z+build.',
    );
  }
  final version = match.group(1)!;
  final build = int.tryParse(match.group(2)!);
  if (!_versionPattern.hasMatch(version) || build == null || build < 1) {
    throw const FormatException(
        'La versión o el build de pubspec.yaml no son válidos.');
  }
  return PubspecReleaseVersion(version, build);
}

int compareVersions(String left, String right) {
  List<int> parts(String value) => value
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((part) => int.tryParse(part) ?? -1)
      .toList();
  final a = parts(left);
  final b = parts(right);
  final length = a.length > b.length ? a.length : b.length;
  for (var index = 0; index < length; index++) {
    final comparison = (index < a.length ? a[index] : 0)
        .compareTo(index < b.length ? b[index] : 0);
    if (comparison != 0) return comparison;
  }
  return 0;
}

Future<Map<String, dynamic>> createAndroidReleaseManifest({
  required File pubspec,
  required File template,
  required File apk,
  required String requestedVersion,
  required String minimumSupportedVersion,
  required bool mandatory,
  required String title,
  required String description,
  required DateTime publishedAt,
}) async {
  if (!await pubspec.exists()) {
    throw StateError('No existe ${pubspec.path}.');
  }
  if (!await template.exists()) {
    throw StateError('No existe la plantilla versionada ${template.path}.');
  }
  if (!await apk.exists() || await apk.length() < 1024) {
    throw StateError('Falta el APK release o el archivo no es válido.');
  }
  final apkName = apk.uri.pathSegments.last;
  if (!_apkNamePattern.hasMatch(apkName)) {
    throw const FormatException(
        'El APK debe tener un nombre base seguro terminado en .apk.');
  }

  final pubspecVersion = parsePubspecVersion(await pubspec.readAsString());
  if (requestedVersion.trim() != pubspecVersion.version) {
    throw FormatException(
      'La versión solicitada (${requestedVersion.trim()}) no coincide con '
      'pubspec.yaml (${pubspecVersion.version}).',
    );
  }
  final minimum = minimumSupportedVersion.trim();
  if (!_versionPattern.hasMatch(minimum) ||
      compareVersions(minimum, pubspecVersion.version) > 0) {
    throw const FormatException(
      'minimumSupportedVersion debe ser válida y no superar la versión publicada.',
    );
  }
  final cleanTitle = title.trim();
  final cleanDescription = description.trim();
  if (cleanTitle.isEmpty || cleanTitle.length > 120) {
    throw const FormatException(
        'El título es obligatorio y admite hasta 120 caracteres.');
  }
  if (cleanDescription.isEmpty || cleanDescription.length > 8000) {
    throw const FormatException(
      'La descripción es obligatoria y admite hasta 8000 caracteres.',
    );
  }
  if (!publishedAt.isUtc) {
    throw const FormatException('publishedAt debe expresarse en UTC.');
  }

  final templateJson = jsonDecode(await template.readAsString());
  if (templateJson is! Map<String, dynamic> ||
      templateJson.keys.toSet().difference(manifestKeys).isNotEmpty ||
      manifestKeys.difference(templateJson.keys.toSet()).isNotEmpty) {
    throw const FormatException(
        'La plantilla versionada no tiene el contrato esperado.');
  }
  final digest = await sha256.bind(apk.openRead()).first;
  final manifest = <String, dynamic>{
    'version': pubspecVersion.version,
    'buildNumber': pubspecVersion.buildNumber,
    'minimumSupportedVersion': minimum,
    'mandatory': mandatory,
    'title': cleanTitle,
    'description': cleanDescription,
    'apkFile': apkName,
    'sha256': digest.toString(),
    'publishedAt': publishedAt.toUtc().toIso8601String(),
  };
  if ((manifest['sha256'] as String).length != 64) {
    throw StateError('No se pudo calcular el SHA-256 del APK.');
  }
  return manifest;
}

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseArguments(arguments);
    final manifest = await createAndroidReleaseManifest(
      pubspec: File(options['pubspec']!),
      template: File(options['template']!),
      apk: File(options['apk']!),
      requestedVersion: options['version']!,
      minimumSupportedVersion: options['minimum-supported-version']!,
      mandatory: _parseBool(options['mandatory']!),
      title: options['title']!,
      description: options['description']!,
      publishedAt: DateTime.parse(options['published-at']!).toUtc(),
    );
    final output = File(options['output']!);
    await output.parent.create(recursive: true);
    final partial = File('${output.path}.tmp');
    await partial.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
      flush: true,
    );
    if (await output.exists()) await output.delete();
    await partial.rename(output.path);
    stdout.writeln('Manifiesto validado: ${output.path}');
  } on Object catch (error) {
    stderr.writeln('ERROR: $error');
    exitCode = 64;
  }
}

Map<String, String> _parseArguments(List<String> arguments) {
  const required = <String>{
    'pubspec',
    'template',
    'apk',
    'output',
    'version',
    'minimum-supported-version',
    'mandatory',
    'title',
    'description',
    'published-at',
  };
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    if (index + 1 >= arguments.length || !arguments[index].startsWith('--')) {
      throw const FormatException('Los argumentos deben usar --nombre valor.');
    }
    result[arguments[index].substring(2)] = arguments[index + 1];
  }
  final missing = required.difference(result.keys.toSet());
  if (missing.isNotEmpty) {
    throw FormatException('Faltan argumentos: ${missing.join(', ')}.');
  }
  return result;
}

bool _parseBool(String value) => switch (value.toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => throw const FormatException('mandatory debe ser true o false.'),
    };
