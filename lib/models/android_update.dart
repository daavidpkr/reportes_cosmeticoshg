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
    required this.minimumSupportedVersion,
    required this.description,
    required this.mandatory,
    required this.apkAssetName,
    required this.apkSize,
    required this.apkSha256,
    required this.apkUrl,
    required this.releaseUrl,
    required this.publishedAt,
  });

  static final _sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');
  static final _versionPattern =
      RegExp(r'^\d+(?:\.\d+){1,3}(?:[-+][0-9A-Za-z.-]+)?$');
  static final _safeApkName =
      RegExp(r'^[0-9A-Za-z][0-9A-Za-z._-]{0,119}\.apk$');

  final String title;
  final String version;
  final int build;
  final String minimumSupportedVersion;
  final String description;
  final bool mandatory;
  final String apkAssetName;
  final int apkSize;
  final String apkSha256;
  final String apkUrl;
  final String releaseUrl;
  final DateTime publishedAt;

  bool isNewerThan(InstalledAndroidVersion installed) =>
      build > installed.build &&
      compareVersions(version, installed.version) >= 0;

  int compareReleaseTo(AndroidUpdateManifest other) {
    final versionComparison = compareVersions(version, other.version);
    return versionComparison != 0
        ? versionComparison
        : build.compareTo(other.build);
  }

  bool isMandatoryFor(InstalledAndroidVersion installed) =>
      mandatory &&
      isNewerThan(installed) &&
      compareVersions(installed.version, minimumSupportedVersion) < 0;

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
    if (manifest['version'] is! String ||
        manifest['buildNumber'] is! int ||
        manifest['minimumSupportedVersion'] is! String ||
        manifest['description'] is! String ||
        manifest['mandatory'] is! bool ||
        manifest['title'] is! String ||
        manifest['apkFile'] is! String ||
        manifest['sha256'] is! String ||
        manifest['publishedAt'] is! String) {
      throw const FormatException(
          'El manifiesto de actualización está incompleto.');
    }
    final title = (manifest['title'] as String).trim();
    final version = (manifest['version'] as String).trim();
    final build = manifest['buildNumber'] as int;
    final minimumSupportedVersion =
        (manifest['minimumSupportedVersion'] as String).trim();
    final description = (manifest['description'] as String).trim();
    final asset = (manifest['apkFile'] as String).trim();
    final sha256 = (manifest['sha256'] as String).trim().toLowerCase();
    final publishedAt = DateTime.tryParse(
      (manifest['publishedAt'] as String).trim(),
    );
    if (title.isEmpty ||
        title.length > 120 ||
        description.isEmpty ||
        description.length > 8000 ||
        !_versionPattern.hasMatch(version) ||
        !_versionPattern.hasMatch(minimumSupportedVersion) ||
        compareVersions(minimumSupportedVersion, version) > 0 ||
        build < 1 ||
        !_safeApkName.hasMatch(asset) ||
        releaseAssetSize < 1024 ||
        !_sha256Pattern.hasMatch(sha256) ||
        publishedAt == null ||
        !publishedAt.isUtc ||
        !(manifest['publishedAt'] as String).trim().endsWith('Z') ||
        !_isTrustedReleaseUrl(apkUrl, asset) ||
        !_isTrustedPageUrl(releaseUrl)) {
      throw const FormatException(
          'El manifiesto de actualización contiene datos no válidos.');
    }
    return AndroidUpdateManifest(
      title: title,
      version: version,
      build: build,
      minimumSupportedVersion: minimumSupportedVersion,
      description: description,
      mandatory: manifest['mandatory'] as bool,
      apkAssetName: asset,
      apkSize: releaseAssetSize,
      apkSha256: sha256,
      apkUrl: apkUrl,
      releaseUrl: releaseUrl,
      publishedAt: publishedAt,
    );
  }

  factory AndroidUpdateManifest.fromCache(Map<String, dynamic> json) =>
      AndroidUpdateManifest.fromRelease(
        manifest: json,
        apkUrl: json['cached_apk_url'] as String? ?? '',
        releaseAssetSize: json['cached_apk_size'] as int? ?? 0,
        releaseUrl: json['cached_release_url'] as String? ?? '',
      );

  Map<String, dynamic> toCacheJson() => <String, dynamic>{
        'title': title,
        'version': version,
        'buildNumber': build,
        'minimumSupportedVersion': minimumSupportedVersion,
        'description': description,
        'mandatory': mandatory,
        'apkFile': apkAssetName,
        'sha256': apkSha256,
        'publishedAt': publishedAt.toUtc().toIso8601String(),
        'cached_apk_url': apkUrl,
        'cached_apk_size': apkSize,
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
