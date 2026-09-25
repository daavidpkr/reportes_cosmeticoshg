import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'web_download_stub.dart'
    if (dart.library.js_interop) 'web_download.dart';

class SavedDocument {
  const SavedDocument({required this.name, required this.location});

  final String name;
  final String location;

  String get confirmationMessage => kIsWeb
      ? 'Archivo descargado: $name'
      : defaultTargetPlatform == TargetPlatform.android
          ? 'Archivo guardado en Descargas: $name'
          : 'Archivo guardado en: $location';
}

/// Punto único de salida para los documentos generados por la aplicación.
/// Android delega en MediaStore (o en Download para Android antiguo), mientras
/// web y escritorio conservan su comportamiento previo.
class DocumentDownloadService {
  DocumentDownloadService({
    MethodChannel? androidChannel,
    TargetPlatform? platformOverride,
    Future<Directory> Function()? documentsDirectory,
  })  : _androidChannel = androidChannel ?? _channel,
        _platformOverride = platformOverride,
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  static const _channel = MethodChannel(
    'com.example.reportes_cosmeticoshg/document_downloads',
  );

  final MethodChannel _androidChannel;
  final TargetPlatform? _platformOverride;
  final Future<Directory> Function() _documentsDirectory;

  TargetPlatform get _platform => _platformOverride ?? defaultTargetPlatform;

  Future<SavedDocument> save({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final cleanName = fileName.trim();
    if (cleanName.isEmpty ||
        cleanName == '.' ||
        cleanName == '..' ||
        cleanName.contains('/') ||
        cleanName.contains('\\')) {
      throw const FormatException('El nombre del archivo no es válido.');
    }
    if (bytes.isEmpty) {
      throw const FormatException('El documento está vacío.');
    }

    if (kIsWeb) {
      descargarArchivoWeb(bytes, cleanName);
      return SavedDocument(name: cleanName, location: cleanName);
    }

    if (_platform == TargetPlatform.android) {
      final response = await _androidChannel.invokeMapMethod<String, dynamic>(
        'saveDocument',
        <String, dynamic>{
          'bytes': bytes,
          'fileName': cleanName,
          'mimeType': mimeType,
        },
      );
      final savedName = response?['name']?.toString().trim() ?? '';
      if (savedName.isEmpty) {
        throw const FileSystemException(
          'Android no confirmó el archivo guardado.',
        );
      }
      return SavedDocument(
        name: savedName,
        location: response?['location']?.toString() ?? 'Descargas/$savedName',
      );
    }

    final directory = await _documentsDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}$cleanName',
    );
    await file.writeAsBytes(bytes, flush: true);
    return SavedDocument(name: cleanName, location: file.path);
  }
}
