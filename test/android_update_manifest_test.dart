import 'package:cosmeticos_hg_reportes/models/android_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const apkUrl =
      'https://github.com/daavidpkr/reportes_cosmeticoshg/releases/download/v1.1.0/cosmeticos-hg-8.apk';
  const releaseUrl =
      'https://github.com/daavidpkr/reportes_cosmeticoshg/releases/tag/v1.1.0';

  Map<String, dynamic> validManifest() => <String, dynamic>{
        'schema_version': 1,
        'title': 'Mejoras de reportes',
        'version': '1.1.0',
        'build': 8,
        'description': 'Incluye correcciones y mejoras de seguridad.',
        'mandatory': false,
        'apk': <String, dynamic>{
          'asset': 'cosmeticos-hg-8.apk',
          'size': 123456,
          'sha256': 'a' * 64,
        },
      };

  test('acepta un manifiesto completo de la release oficial', () {
    final update = AndroidUpdateManifest.fromRelease(
      manifest: validManifest(),
      apkUrl: apkUrl,
      releaseAssetSize: 123456,
      releaseUrl: releaseUrl,
    );

    expect(update.version, '1.1.0');
    expect(
        update.isNewerThan(
          const InstalledAndroidVersion(version: '1.0.3', build: 7),
        ),
        isTrue);
  });

  test('rechaza manifiestos incompletos sin reemplazar datos válidos', () {
    final manifest = validManifest()..remove('description');

    expect(
      () => AndroidUpdateManifest.fromRelease(
        manifest: manifest,
        apkUrl: apkUrl,
        releaseAssetSize: 123456,
        releaseUrl: releaseUrl,
      ),
      throwsFormatException,
    );
  });

  test('rechaza APK de otro repositorio o tamaño distinto', () {
    expect(
      () => AndroidUpdateManifest.fromRelease(
        manifest: validManifest(),
        apkUrl:
            'https://github.com/otro/proyecto/releases/download/v1.1.0/cosmeticos-hg-8.apk',
        releaseAssetSize: 123456,
        releaseUrl: releaseUrl,
      ),
      throwsFormatException,
    );
    expect(
      () => AndroidUpdateManifest.fromRelease(
        manifest: validManifest(),
        apkUrl: apkUrl,
        releaseAssetSize: 999999,
        releaseUrl: releaseUrl,
      ),
      throwsFormatException,
    );
  });

  test('no ofrece una versión semántica inferior aunque aumente el build', () {
    final manifest = validManifest()
      ..['version'] = '0.9.9'
      ..['build'] = 99;
    final update = AndroidUpdateManifest.fromRelease(
      manifest: manifest,
      apkUrl: apkUrl,
      releaseAssetSize: 123456,
      releaseUrl: releaseUrl,
    );

    expect(
      update.isNewerThan(
        const InstalledAndroidVersion(version: '1.0.3', build: 7),
      ),
      isFalse,
    );
  });

  test('la caché vuelve a validarse al leerse', () {
    final update = AndroidUpdateManifest.fromRelease(
      manifest: validManifest(),
      apkUrl: apkUrl,
      releaseAssetSize: 123456,
      releaseUrl: releaseUrl,
    );
    final cached = AndroidUpdateManifest.fromCache(update.toCacheJson());

    expect(cached.apkSha256, 'a' * 64);
    expect(cached.apkUrl, apkUrl);
  });
}
