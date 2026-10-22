import '../models/android_update.dart';

class AndroidUpdateService {
  bool get isSupported => false;

  Future<InstalledAndroidVersion> installedVersion() => throw UnsupportedError(
      'Las actualizaciones solo están disponibles en Android.');

  Future<AndroidUpdateManifest> checkLatest() => throw UnsupportedError(
      'Las actualizaciones solo están disponibles en Android.');

  Future<AndroidUpdateManifest?> cachedManifest() async => null;

  Future<String> download(
    AndroidUpdateManifest manifest, {
    required void Function(double progress) onProgress,
  }) =>
      throw UnsupportedError(
          'Las actualizaciones solo están disponibles en Android.');

  void cancelDownload() {}

  Future<bool> canInstallPackages() async => false;

  Future<void> requestInstallPermission() async {}

  Future<void> install(String path) async {}
}
