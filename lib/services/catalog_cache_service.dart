import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog.dart';
import 'catalog_cache_backend.dart';
import 'catalog_file_error.dart';

class CachedCatalogFile {
  const CachedCatalogFile({
    required this.catalog,
    required this.cachedVersion,
    required this.bytes,
    this.localPath,
  });

  final Catalog catalog;
  final int cachedVersion;
  final Uint8List bytes;
  final String? localPath;
  bool get hasNewerVersion => catalog.version > cachedVersion;
}

class CatalogCacheService {
  CatalogCacheService({CatalogCacheBackend? backend})
      : _backend = backend ?? CatalogCacheBackend();

  static const _metadataKey = 'catalog_cache_metadata_v1';
  static const _cleanupKey = 'catalog_storage_cleanup_queue_v1';
  final CatalogCacheBackend _backend;

  String _pdfKey(String id, int version) => '$id/v$version/catalogo.pdf';
  String _coverKey(String id, int version) => '$id/v$version/portada';

  Future<Map<String, dynamic>> _metadata() async {
    final raw = (await SharedPreferences.getInstance()).getString(_metadataKey);
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveMetadata(Map<String, dynamic> value) async =>
      (await SharedPreferences.getInstance())
          .setString(_metadataKey, jsonEncode(value));

  Future<int?> cachedVersion(String id) async {
    final metadata = await _metadata();
    return ((metadata[id] as Map?)?['cached_version'] as num?)?.toInt();
  }

  Future<bool> isDownloaded(Catalog catalog) async {
    final version = await cachedVersion(catalog.id);
    if (version == null) return false;
    final bytes = await _backend.read(_pdfKey(catalog.id, version));
    return bytes != null && isValidPdfBytes(bytes);
  }

  Future<List<Catalog>> cachedCatalogs() async {
    final metadata = await _metadata();
    return metadata.values
        .whereType<Map>()
        .map((value) => Catalog.fromJson(
            Map<String, dynamic>.from(value['catalog'] as Map)))
        .toList();
  }

  Future<CachedCatalogFile?> open(Catalog current) async {
    final metadata = await _metadata();
    final entry = metadata[current.id] as Map?;
    final version = (entry?['cached_version'] as num?)?.toInt();
    if (version == null) return null;
    final bytes = await _backend.read(_pdfKey(current.id, version));
    if (bytes == null) return null;
    if (!isValidPdfBytes(bytes)) {
      await removeLocal(current.id);
      logCatalogFileError(
        CatalogFileStage.cache,
        const FormatException('PDF inválido en caché'),
        catalogId: current.id,
      );
      return null;
    }
    return CachedCatalogFile(
      catalog: current,
      cachedVersion: version,
      bytes: bytes,
      localPath: await _backend.localPath(_pdfKey(current.id, version)),
    );
  }

  Future<void> store(Catalog catalog, Uint8List pdf, {Uint8List? cover}) async {
    if (!isValidPdfBytes(pdf)) {
      throw const CatalogFileException(
        stage: CatalogFileStage.cache,
        userMessage: 'No se guardó un PDF inválido en la caché.',
      );
    }
    final metadata = await _metadata();
    final previous = (metadata[catalog.id] as Map?)?['cached_version'] as num?;
    await _backend.write(_pdfKey(catalog.id, catalog.version), pdf);
    if (cover != null) {
      await _backend.write(_coverKey(catalog.id, catalog.version), cover);
    }
    metadata[catalog.id] = {
      'cached_version': catalog.version,
      'catalog': catalog.toCacheJson(),
    };
    await _saveMetadata(metadata);
    if (previous != null && previous.toInt() != catalog.version) {
      await _backend.delete(_pdfKey(catalog.id, previous.toInt()));
      await _backend.delete(_coverKey(catalog.id, previous.toInt()));
    }
  }

  Future<Uint8List?> cover(Catalog catalog) async {
    final exact = await _backend.read(_coverKey(catalog.id, catalog.version));
    if (exact != null) return exact;
    final version = await cachedVersion(catalog.id);
    return version == null
        ? null
        : _backend.read(_coverKey(catalog.id, version));
  }

  Future<void> removeLocal(String id) async {
    final metadata = await _metadata();
    final version =
        ((metadata[id] as Map?)?['cached_version'] as num?)?.toInt();
    if (version != null) {
      await _backend.delete(_pdfKey(id, version));
      await _backend.delete(_coverKey(id, version));
    }
    metadata.remove(id);
    await _saveMetadata(metadata);
  }

  Future<void> queueStorageCleanup(Iterable<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    final queued = prefs.getStringList(_cleanupKey)?.toSet() ?? <String>{};
    queued.addAll(paths.where((path) => path.isNotEmpty));
    await prefs.setStringList(_cleanupKey, queued.toList());
  }

  Future<List<String>> storageCleanupQueue() async =>
      (await SharedPreferences.getInstance()).getStringList(_cleanupKey) ??
      const [];

  Future<void> clearStorageCleanup(Iterable<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    final queued = prefs.getStringList(_cleanupKey)?.toSet() ?? <String>{};
    queued.removeAll(paths);
    await prefs.setStringList(_cleanupKey, queued.toList());
  }
}
