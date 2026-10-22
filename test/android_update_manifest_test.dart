import 'package:cosmeticos_hg_reportes/models/android_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const apkUrl =
      'https://github.com/daavidpkr/reportes_cosmeticoshg/releases/download/v1.1.0/cosmeticos-hg-8.apk';
  const releaseUrl =
      'https://github.com/daavidpkr/reportes_cosmeticoshg/releases/tag/v1.1.0';

  Map<String, dynamic> validManifest() => <String, dynamic>{
        'title': 'Mejoras de reportes',
        'version': '1.1.0',
        'buildNumber': 8,
        'minimumSupportedVersion': '1.0.0',
        'description': 'Incluye correcciones y mejoras de seguridad.',
        'mandatory': false,
        'apkFile': 'cosmeticos-hg-8.apk',
        'sha256': 'a' * 64,
        'publishedAt': '2026-10-22T22:00:00Z',
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

  test('rechaza APK de otro repositorio o un asset vacío', () {
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
        releaseAssetSize: 999,
        releaseUrl: releaseUrl,
      ),
      throwsFormatException,
    );
  });

  test('no ofrece una versión semántica inferior aunque aumente el build', () {
    final manifest = validManifest()
      ..['version'] = '0.9.9'
      ..['minimumSupportedVersion'] = '0.9.0'
      ..['buildNumber'] = 99;
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

  test('solo bloquea cuando mandatory es explícito y la versión es inferior',
      () {
    final manifest = validManifest()
      ..['mandatory'] = true
      ..['minimumSupportedVersion'] = '1.0.4';
    final update = AndroidUpdateManifest.fromRelease(
      manifest: manifest,
      apkUrl: apkUrl,
      releaseAssetSize: 123456,
      releaseUrl: releaseUrl,
    );

    expect(
      update.isMandatoryFor(
        const InstalledAndroidVersion(version: '1.0.3', build: 7),
      ),
      isTrue,
    );
    manifest['mandatory'] = false;
    final optional = AndroidUpdateManifest.fromRelease(
      manifest: manifest,
      apkUrl: apkUrl,
      releaseAssetSize: 123456,
      releaseUrl: releaseUrl,
    );
    expect(
      optional.isMandatoryFor(
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
