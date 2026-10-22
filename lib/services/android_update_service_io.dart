import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/android_update.dart';

class AndroidUpdateService {
  static const _channel =
      MethodChannel('com.example.reportes_cosmeticoshg/updates');
  static const _latestRelease =
      'https://api.github.com/repos/daavidpkr/reportes_cosmeticoshg/releases/latest';
  static const _manifestAsset = 'update_manifest.json';
  static const _cacheKey = 'android_update_manifest_v1';

  http.Client? _downloadClient;
  bool _cancelled = false;

  bool get isSupported => Platform.isAndroid;

  Future<InstalledAndroidVersion> installedVersion() async {
    final data =
        await _channel.invokeMapMethod<String, dynamic>('installedVersion');
    if (data == null || data['version'] is! String || data['build'] is! int) {
      throw const FormatException('Android no devolvió la versión instalada.');
    }
    return InstalledAndroidVersion(
      version: data['version']! as String,
      build: data['build']! as int,
    );
  }

  Future<AndroidUpdateManifest> checkLatest() async {
    final releaseResponse = await http.get(
      Uri.parse(_latestRelease),
      headers: const {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (releaseResponse.statusCode != 200) {
      throw HttpException('GitHub respondió ${releaseResponse.statusCode}.');
    }
    final release = jsonDecode(utf8.decode(releaseResponse.bodyBytes));
    if (release is! Map<String, dynamic> ||
        release['assets'] is! List<dynamic> ||
        release['html_url'] is! String) {
      throw const FormatException('La última release pública no es válida.');
    }
    final assets = release['assets'] as List<dynamic>;
    final manifestAsset = _findAsset(assets, _manifestAsset);
    final manifestUrl = manifestAsset['browser_download_url'] as String?;
    if (!_trustedManifestUrl(manifestUrl)) {
      throw const FormatException(
          'El manifiesto no pertenece a la release esperada.');
    }
    final manifestResponse = await http.get(Uri.parse(manifestUrl!),
        headers: const {
          'Accept': 'application/json'
        }).timeout(const Duration(seconds: 15));
    if (manifestResponse.statusCode != 200 ||
        manifestResponse.bodyBytes.length > 100000) {
      throw const FormatException(
          'No se pudo leer el manifiesto de actualización.');
    }
    final decoded = jsonDecode(utf8.decode(manifestResponse.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['apkFile'] is! String) {
      throw const FormatException(
          'El manifiesto de actualización está incompleto.');
    }
    final apkName = decoded['apkFile'] as String;
    final apkAsset = _findAsset(assets, apkName);
    final result = AndroidUpdateManifest.fromRelease(
      manifest: decoded,
      apkUrl: apkAsset['browser_download_url'] as String? ?? '',
      releaseAssetSize: apkAsset['size'] as int? ?? 0,
      releaseUrl: release['html_url'] as String,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, result.encodeForCache());
    return result;
  }

  Future<AndroidUpdateManifest?> cachedManifest() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return AndroidUpdateManifest.fromCache(decoded);
    } on Object {
      return null;
    }
  }

  Future<String> download(
    AndroidUpdateManifest manifest, {
    required void Function(double progress) onProgress,
  }) async {
    cancelDownload();
    _cancelled = false;
    final client = http.Client();
    _downloadClient = client;
    final directory = await _channel.invokeMethod<String>(
      'prepareDownload',
      {'build': manifest.build},
    );
    if (directory == null) {
      throw const FileSystemException('Android no preparó la descarga.');
    }
    final partial = File(
        '$directory${Platform.pathSeparator}update-${manifest.build}.part');
    final target =
        File('$directory${Platform.pathSeparator}update-${manifest.build}.apk');
    try {
      if (await partial.exists()) await partial.delete();
      if (await target.exists()) await target.delete();
      final request = http.Request('GET', Uri.parse(manifest.apkUrl));
      request.headers['Accept'] = 'application/vnd.android.package-archive';
      final response =
          await client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw HttpException('La descarga respondió ${response.statusCode}.');
      }
      final declaredLength = response.contentLength;
      if (declaredLength != null && declaredLength != manifest.apkSize) {
        throw const FormatException(
            'El tamaño publicado no coincide con el APK.');
      }
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          if (_cancelled) throw const _DownloadCancelled();
          received += chunk.length;
          if (received > manifest.apkSize) {
            throw const FormatException('El APK excede el tamaño declarado.');
          }
          sink.add(chunk);
          onProgress(received / manifest.apkSize);
        }
      } finally {
        await sink.close();
      }
      if (_cancelled) throw const _DownloadCancelled();
      if (received != manifest.apkSize) {
        throw const FormatException('La descarga quedó incompleta.');
      }
      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString() != manifest.apkSha256) {
        throw const FormatException('El SHA-256 del APK no coincide.');
      }
      await partial.rename(target.path);
      final valid = await _channel.invokeMethod<bool>('validateApk', {
            'path': target.path,
            'build': manifest.build,
            'version': manifest.version,
          }) ??
          false;
      if (!valid) {
        await target.delete();
        throw const FormatException(
            'El archivo no es un APK válido para esta aplicación.');
      }
      onProgress(1);
      return target.path;
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      client.close();
      if (identical(_downloadClient, client)) _downloadClient = null;
    }
  }

  void cancelDownload() {
    _cancelled = true;
    _downloadClient?.close();
    _downloadClient = null;
  }

  Future<bool> canInstallPackages() async =>
      await _channel.invokeMethod<bool>('canInstallPackages') ?? false;

  Future<void> requestInstallPermission() =>
      _channel.invokeMethod<void>('requestInstallPermission');

  Future<void> install(String path) =>
      _channel.invokeMethod<void>('installApk', {'path': path});

  Map<String, dynamic> _findAsset(List<dynamic> assets, String name) {
    final matches = assets.whereType<Map<String, dynamic>>().where(
          (asset) => asset['name'] == name && asset['state'] == 'uploaded',
        );
    if (matches.length != 1) {
      throw FormatException(
          'La release debe contener exactamente un asset $name.');
    }
    return matches.single;
  }

  bool _trustedManifestUrl(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.path.startsWith(
            '/daavidpkr/reportes_cosmeticoshg/releases/download/') &&
        uri.pathSegments.last == _manifestAsset;
  }
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();

  @override
  String toString() => 'Descarga cancelada.';
}
