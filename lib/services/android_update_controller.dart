import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/android_update.dart';
import 'android_update_service.dart';

enum AndroidUpdateStatus {
  idle,
  checking,
  current,
  available,
  downloading,
  ready,
  permissionNeeded,
  cancelled,
  error,
}

class AndroidUpdateController extends ChangeNotifier {
  AndroidUpdateController._();

  static final instance = AndroidUpdateController._();

  final AndroidUpdateService _service = AndroidUpdateService();
  AndroidUpdateStatus status = AndroidUpdateStatus.idle;
  InstalledAndroidVersion? installed;
  AndroidUpdateManifest? manifest;
  double progress = 0;
  String? message;
  String? _apkPath;
  bool _started = false;

  bool get isSupported => _service.isSupported;
  bool get blocksNormalUse {
    final current = installed;
    final update = manifest;
    return current != null && update != null && update.isMandatoryFor(current);
  }

  Future<void> start() async {
    if (_started || !isSupported) return;
    _started = true;
    await check();
  }

  Future<void> check() async {
    if (!isSupported) return;
    status = AndroidUpdateStatus.checking;
    message = null;
    notifyListeners();
    try {
      installed ??= await _service.installedVersion();
      manifest = await _service.checkLatest();
      _applyManifest();
    } catch (error) {
      final cached = await _service.cachedManifest();
      if (cached != null && installed != null) {
        manifest = cached;
        message =
            'Sin conexión con GitHub. Se muestra la última información válida guardada.';
        _applyManifest(keepMessage: true);
      } else {
        status = AndroidUpdateStatus.error;
        message = _friendlyError(error, checking: true);
        notifyListeners();
      }
    }
  }

  void _applyManifest({bool keepMessage = false}) {
    final current = installed;
    final update = manifest;
    if (current == null || update == null) return;
    status = update.isNewerThan(current)
        ? AndroidUpdateStatus.available
        : AndroidUpdateStatus.current;
    if (!keepMessage) message = null;
    notifyListeners();
  }

  Future<void> download() async {
    final update = manifest;
    if (update == null ||
        installed == null ||
        !update.isNewerThan(installed!)) {
      return;
    }
    status = AndroidUpdateStatus.downloading;
    progress = 0;
    message = null;
    notifyListeners();
    try {
      _apkPath = await _service.download(
        update,
        onProgress: (value) {
          progress = value.clamp(0, 1);
          notifyListeners();
        },
      );
      status = AndroidUpdateStatus.ready;
      message = 'APK descargado y verificado. Ya puedes abrir el instalador.';
    } catch (error) {
      if (status == AndroidUpdateStatus.cancelled) return;
      status = AndroidUpdateStatus.error;
      message = _friendlyError(error);
    }
    notifyListeners();
  }

  void cancel() {
    if (status != AndroidUpdateStatus.downloading) return;
    status = AndroidUpdateStatus.cancelled;
    message = 'Descarga cancelada. Puedes intentarlo de nuevo.';
    _service.cancelDownload();
    notifyListeners();
  }

  Future<void> install() async {
    final path = _apkPath;
    if (path == null) {
      await download();
      return;
    }
    try {
      if (!await _service.canInstallPackages()) {
        status = AndroidUpdateStatus.permissionNeeded;
        message =
            'Autoriza a esta aplicación para instalar el APK y vuelve para continuar.';
        notifyListeners();
        await _service.requestInstallPermission();
        return;
      }
      status = AndroidUpdateStatus.ready;
      message = 'Instalador abierto. Android pedirá tu confirmación.';
      notifyListeners();
      await _service.install(path);
    } catch (error) {
      status = AndroidUpdateStatus.error;
      message = _friendlyError(error);
      notifyListeners();
    }
  }

  String _friendlyError(Object error, {bool checking = false}) {
    if (checking) {
      return 'No se pudo consultar la actualización. Revisa la conexión e inténtalo de nuevo.';
    }
    if (error.toString().contains('cancel')) {
      return 'Descarga cancelada. Puedes intentarlo de nuevo.';
    }
    return 'No se pudo completar la actualización. El archivo fue descartado; inténtalo de nuevo.';
  }
}
