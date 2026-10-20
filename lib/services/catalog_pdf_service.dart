import 'dart:async';
import 'dart:typed_data';

import '../models/catalog.dart';
import 'catalog_cache_service.dart';
import 'catalog_file_error.dart';
import 'catalog_repository.dart';

/// Punto único para obtener un PDF utilizable por cualquier acción.
class CatalogPdfService {
  CatalogPdfService({
    required CatalogRepository repository,
    required CatalogCacheService cache,
  })  : _repository = repository,
        _cache = cache;

  final CatalogRepository _repository;
  final CatalogCacheService _cache;
  final Map<String, Future<CachedCatalogFile>> _inFlight = {};

  Future<CachedCatalogFile> obtain(
    Catalog catalog, {
    void Function(double)? onProgress,
    Future<Uint8List?> Function()? loadCover,
  }) {
    final key = '${catalog.id}:v${catalog.version}';
    final current = _inFlight[key];
    if (current != null) return current;
    final future = _obtain(
      catalog,
      onProgress: onProgress,
      loadCover: loadCover,
    );
    _inFlight[key] = future;
    void clear() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }

    unawaited(future.then<void>(
      (_) => clear(),
      onError: (Object _, StackTrace __) => clear(),
    ));
    return future;
  }

  Future<CachedCatalogFile> _obtain(
    Catalog catalog, {
    void Function(double)? onProgress,
    Future<Uint8List?> Function()? loadCover,
  }) async {
    CachedCatalogFile? cached;
    try {
      cached = await _cache.open(catalog);
    } catch (error) {
      logCatalogFileError(CatalogFileStage.cache, error, catalogId: catalog.id);
    }
    if (cached != null && cached.cachedVersion == catalog.version) {
      return cached;
    }
    if (!catalog.canOpen) {
      throw const CatalogFileException(
        stage: CatalogFileStage.metadata,
        userMessage: 'Archivo pendiente de publicación.',
      );
    }

    try {
      final pdf = await _repository.download(
        catalog.filePath!,
        onProgress: onProgress,
        requirePdf: true,
      );
      Uint8List? cover;
      if (loadCover != null) {
        try {
          cover = await loadCover();
        } catch (error) {
          logCatalogFileError(CatalogFileStage.cache, error,
              catalogId: catalog.id);
        }
      }
      try {
        await _cache.store(catalog, pdf, cover: cover);
        return await _cache.open(catalog) ?? _memoryFile(catalog, pdf);
      } catch (error) {
        logCatalogFileError(CatalogFileStage.cache, error,
            catalogId: catalog.id);
        return _memoryFile(catalog, pdf);
      }
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  CachedCatalogFile _memoryFile(Catalog catalog, Uint8List bytes) =>
      CachedCatalogFile(
        catalog: catalog,
        cachedVersion: catalog.version,
        bytes: Uint8List.fromList(bytes),
      );
}
