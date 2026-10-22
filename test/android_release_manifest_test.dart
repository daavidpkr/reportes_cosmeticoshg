import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/android_release_manifest.dart';

void main() {
  late Directory temporary;
  late File pubspec;
  late File template;
  late File apk;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('android-release-test-');
    pubspec = File('${temporary.path}/pubspec.yaml')
      ..writeAsStringSync('name: test\nversion: 1.2.3+12\n');
    template = File('${temporary.path}/update_manifest.v1.template.json')
      ..writeAsStringSync(jsonEncode(<String, dynamic>{
        for (final key in manifestKeys) key: null,
      }));
    apk = File('${temporary.path}/cosmeticos-hg-1.2.3-12.apk')
      ..writeAsBytesSync(List<int>.generate(2048, (index) => index % 251));
  });

  tearDown(() => temporary.delete(recursive: true));

  test('genera metadatos desde pubspec y calcula el SHA-256', () async {
    final manifest = await createAndroidReleaseManifest(
      pubspec: pubspec,
      template: template,
      apk: apk,
      requestedVersion: '1.2.3',
      minimumSupportedVersion: '1.0.0',
      mandatory: true,
      title: 'Actualización de seguridad',
      description: 'Corrige un problema crítico.',
      publishedAt: DateTime.utc(2026, 10, 22, 22),
    );

    expect(manifest['buildNumber'], 12);
    expect(manifest['mandatory'], isTrue);
    expect(manifest['apkFile'], apk.uri.pathSegments.last);
    expect(
        manifest['sha256'], sha256.convert(await apk.readAsBytes()).toString());
    expect(manifest.keys.toSet(), manifestKeys);
  });

  test('rechaza una versión distinta de pubspec.yaml', () async {
    expect(
      () => createAndroidReleaseManifest(
        pubspec: pubspec,
        template: template,
        apk: apk,
        requestedVersion: '1.2.4',
        minimumSupportedVersion: '1.0.0',
        mandatory: false,
        title: 'Novedades',
        description: 'Descripción.',
        publishedAt: DateTime.utc(2026),
      ),
      throwsFormatException,
    );
  });

  test('rechaza un APK ausente', () async {
    await apk.delete();
    expect(
      () => createAndroidReleaseManifest(
        pubspec: pubspec,
        template: template,
        apk: apk,
        requestedVersion: '1.2.3',
        minimumSupportedVersion: '1.0.0',
        mandatory: false,
        title: 'Novedades',
        description: 'Descripción.',
        publishedAt: DateTime.utc(2026),
      ),
      throwsStateError,
    );
  });

  test('rechaza metadatos obligatorios incompletos', () async {
    expect(
      () => createAndroidReleaseManifest(
        pubspec: pubspec,
        template: template,
        apk: apk,
        requestedVersion: '1.2.3',
        minimumSupportedVersion: '1.0.0',
        mandatory: false,
        title: '',
        description: '',
        publishedAt: DateTime.utc(2026),
      ),
      throwsFormatException,
    );
  });
}
