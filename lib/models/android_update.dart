import 'dart:convert';

class InstalledAndroidVersion {
  const InstalledAndroidVersion({
    required this.version,
    required this.build,
  });

  final String version;
  final int build;
}

class AndroidUpdateManifest {
  const AndroidUpdateManifest({
    required this.title,
    required this.version,
    required this.build,
    required this.description,
    required this.mandatory,
    required this.apkAssetName,
    required this.apkSize,
    required this.apkSha256,
    required this.apkUrl,
    required this.releaseUrl,
  });

  static final _sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');
  static final _versionPattern =
      RegExp(r'^\d+(?:\.\d+){1,3}(?:[-+][0-9A-Za-z.-]+)?$');
  static final _safeApkName =
      RegExp(r'^[0-9A-Za-z][0-9A-Za-z._-]{0,119}\.apk$');

  final String title;
  final String version;
  final int build;
  final String description;
  final bool mandatory;
  final String apkAssetName;
  final int apkSize;
  final String apkSha256;
  final String apkUrl;
  final String releaseUrl;

  bool isNewerThan(InstalledAndroidVersion installed) =>
      build > installed.build &&
      compareVersions(version, installed.version) >= 0;

  static int compareVersions(String left, String right) {
    List<int> parts(String value) {
      final core = value.split(RegExp(r'[-+]')).first;
      return core.split('.').map((part) => int.tryParse(part) ?? -1).toList();
    }

    final a = parts(left);
    final b = parts(right);
    final length = a.length > b.length ? a.length : b.length;
    for (var index = 0; index < length; index++) {
      final leftPart = index < a.length ? a[index] : 0;
      final rightPart = index < b.length ? b[index] : 0;
      if (leftPart != rightPart) return leftPart.compareTo(rightPart);
    }
    return 0;
  }

  factory AndroidUpdateManifest.fromRelease({
    required Map<String, dynamic> manifest,
    required String apkUrl,
    required int releaseAssetSize,
    required String releaseUrl,
  }) {
    if (manifest['schema_version'] != 1 ||
        manifest['title'] is! String ||
        manifest['version'] is! String ||
        manifest['build'] is! int ||
        manifest['description'] is! String ||
        manifest['mandatory'] is! bool ||
        manifest['apk'] is! Map<String, dynamic>) {
      throw const FormatException(
          'El manifiesto de actualización está incompleto.');
    }
    final apk = manifest['apk'] as Map<String, dynamic>;
    if (apk['asset'] is! String ||
        apk['size'] is! int ||
        apk['sha256'] is! String) {
      throw const FormatException('Los datos del APK están incompletos.');
    }
    final title = (manifest['title'] as String).trim();
    final version = (manifest['version'] as String).trim();
    final build = manifest['build'] as int;
    final description = (manifest['description'] as String).trim();
    final asset = (apk['asset'] as String).trim();
    final size = apk['size'] as int;
    final sha256 = (apk['sha256'] as String).trim().toLowerCase();
    if (title.isEmpty ||
        title.length > 120 ||
        description.isEmpty ||
        description.length > 8000 ||
        !_versionPattern.hasMatch(version) ||
        build < 1 ||
        !_safeApkName.hasMatch(asset) ||
        size < 1024 ||
        size != releaseAssetSize ||
        !_sha256Pattern.hasMatch(sha256) ||
        !_isTrustedReleaseUrl(apkUrl, asset) ||
        !_isTrustedPageUrl(releaseUrl)) {
      throw const FormatException(
          'El manifiesto de actualización contiene datos no válidos.');
    }
    return AndroidUpdateManifest(
      title: title,
      version: version,
      build: build,
      description: description,
      mandatory: manifest['mandatory'] as bool,
      apkAssetName: asset,
      apkSize: size,
      apkSha256: sha256,
      apkUrl: apkUrl,
      releaseUrl: releaseUrl,
    );
  }

  factory AndroidUpdateManifest.fromCache(Map<String, dynamic> json) =>
      AndroidUpdateManifest.fromRelease(
        manifest: json,
        apkUrl: json['cached_apk_url'] as String? ?? '',
        releaseAssetSize:
            ((json['apk'] as Map<String, dynamic>?)?['size'] as int?) ?? 0,
        releaseUrl: json['cached_release_url'] as String? ?? '',
      );

  Map<String, dynamic> toCacheJson() => <String, dynamic>{
        'schema_version': 1,
        'title': title,
        'version': version,
        'build': build,
        'description': description,
        'mandatory': mandatory,
        'apk': <String, dynamic>{
          'asset': apkAssetName,
          'size': apkSize,
          'sha256': apkSha256,
        },
        'cached_apk_url': apkUrl,
        'cached_release_url': releaseUrl,
      };

  String encodeForCache() => jsonEncode(toCacheJson());

  static bool _isTrustedReleaseUrl(String value, String asset) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.pathSegments.length >= 6 &&
        uri.pathSegments[0] == 'daavidpkr' &&
        uri.pathSegments[1] == 'reportes_cosmeticoshg' &&
        uri.pathSegments[2] == 'releases' &&
        uri.pathSegments[3] == 'download' &&
        uri.pathSegments.last == asset;
  }

  static bool _isTrustedPageUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.path.startsWith('/daavidpkr/reportes_cosmeticoshg/releases/');
  }
}
