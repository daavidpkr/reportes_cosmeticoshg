import 'dart:convert';
import 'dart:io';

import 'package:cosmeticos_hg_reportes/services/android_update_service_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> manifest(String version, int build) => {
        'title': 'Cosmeticos HG $version',
        'version': version,
        'buildNumber': build,
        'minimumSupportedVersion': '1.0.0',
        'description': 'Actualizacion $version.',
        'mandatory': false,
        'apkFile': 'cosmeticos-hg-$version-$build.apk',
        'sha256': 'a' * 64,
        'publishedAt': '2026-10-25T12:00:00Z',
      };

  Map<String, dynamic> release(String version, int build) {
    final tag = 'android-v$version-$build';
    final base =
        'https://github.com/daavidpkr/reportes_cosmeticoshg/releases/download/$tag';
    return {
      'tag_name': tag,
      'draft': false,
      'prerelease': false,
      'html_url':
          'https://github.com/daavidpkr/reportes_cosmeticoshg/releases/tag/$tag',
      'assets': [
        {
          'name': 'update_manifest.json',
          'state': 'uploaded',
          'browser_download_url': '$base/update_manifest.json',
        },
        {
          'name': 'cosmeticos-hg-$version-$build.apk',
          'state': 'uploaded',
          'size': 123456,
          'digest': 'sha256:${'a' * 64}',
          'browser_download_url': '$base/cosmeticos-hg-$version-$build.apk',
        },
      ],
    };
  }

  AndroidUpdateService serviceFor(
    List<Map<String, dynamic>> releases, {
    Set<String> invalidManifests = const {},
  }) =>
      AndroidUpdateService(
        httpClient: MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            return http.Response(jsonEncode(releases), 200);
          }
          final tag = request.url.pathSegments[4];
          if (invalidManifests.contains(tag)) {
            return http.Response('{invalid', 200);
          }
          final match =
              RegExp(r'android-v(\d+\.\d+\.\d+)-(\d+)$').firstMatch(tag)!;
          return http.Response(
            jsonEncode(manifest(match.group(1)!, int.parse(match.group(2)!))),
            200,
          );
        }),
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('salta varias versiones y elige la mayor, no la primera recibida',
      () async {
    final latest = await serviceFor([
      release('1.4.0', 13),
      release('1.6.0', 16),
      release('1.5.0', 14),
    ]).checkLatest();

    expect(latest.version, '1.6.0');
    expect(latest.build, 16);
  });

  test('el build mayor resuelve un empate de versión', () async {
    final latest = await serviceFor([
      release('1.6.0', 15),
      release('1.6.0', 16),
    ]).checkLatest();

    expect(latest.build, 16);
  });

  test('ignora una release inválida y usa la anterior válida', () async {
    final latest = await serviceFor(
      [release('1.7.0', 17), release('1.6.0', 16)],
      invalidManifests: {'android-v1.7.0-17'},
    ).checkLatest();

    expect(latest.version, '1.6.0');
    expect(latest.build, 16);
  });

  test('ignora SHA publicado incorrecto y usa la anterior válida', () async {
    final invalid = release('1.7.0', 17);
    (invalid['assets'] as List<dynamic>)[1]['digest'] = 'sha256:${'b' * 64}';

    final latest = await serviceFor([
      invalid,
      release('1.6.0', 16),
    ]).checkLatest();

    expect(latest.version, '1.6.0');
  });

  test('un fallo de consulta conserva la última caché válida', () async {
    await serviceFor([release('1.6.0', 16)]).checkLatest();
    final offline = AndroidUpdateService(
      httpClient: MockClient(
        (_) async => throw const SocketException('offline'),
      ),
    );

    await expectLater(offline.checkLatest(), throwsA(isA<SocketException>()));
    final cached = await offline.cachedManifest();

    expect(cached?.version, '1.6.0');
    expect(cached?.build, 16);
  });
}
