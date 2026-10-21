import 'dart:typed_data';

import 'package:cosmeticos_hg_reportes/models/catalog.dart';
import 'package:cosmeticos_hg_reportes/services/catalog_cache_backend.dart';
import 'package:cosmeticos_hg_reportes/services/catalog_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Backend extends CatalogCacheBackend {
  final files = <String, Uint8List>{};
  String? failingKey;

  @override
  Future<void> delete(String key) async => files.remove(key);
  @override
  Future<String?> localPath(String key) async =>
      files.containsKey(key) ? key : null;
  @override
  Future<Uint8List?> read(String key) async => files[key];
  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (key == failingKey) throw StateError('sin espacio');
    files[key] = bytes;
  }
}

Uint8List pdfBytes(int marker) =>
    Uint8List.fromList([...'%PDF-1.7\n'.codeUnits, marker]);

Catalog version(int value) => Catalog(
      id: 'id',
      organizationId: 'org',
      title: 'Catálogo',
      filePath: 'org/id/v$value/catalogo.pdf',
      coverPath: 'org/id/v$value/portada.webp',
      version: value,
      pageCount: 1,
      status: CatalogStatus.publicado,
      active: true,
      order: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 10, 19),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reemplaza la caché sólo después de guardar la versión nueva', () async {
    final backend = _Backend();
    final cache = CatalogCacheService(backend: backend);
    await cache.store(version(1), pdfBytes(1));
    backend.failingKey = 'id/v2/catalogo.pdf';

    await expectLater(cache.store(version(2), pdfBytes(2)), throwsStateError);
    expect((await cache.open(version(2)))?.cachedVersion, 1);
    expect(backend.files['id/v1/catalogo.pdf'], pdfBytes(1));

    backend.failingKey = null;
    await cache.store(version(2), pdfBytes(2));
    expect((await cache.open(version(2)))?.cachedVersion, 2);
    expect(backend.files.containsKey('id/v1/catalogo.pdf'), isFalse);
  });

  test('descarta un PDF vacío o corrupto de la caché', () async {
    final backend = _Backend();
    final cache = CatalogCacheService(backend: backend);
    await cache.store(version(1), pdfBytes(1));
    backend.files['id/v1/catalogo.pdf'] = Uint8List(0);

    expect(await cache.open(version(1)), isNull);
    expect(await cache.isDownloaded(version(1)), isFalse);
    expect(backend.files.containsKey('id/v1/catalogo.pdf'), isFalse);
  });

  test('mantiene una cola deduplicada para limpiar objetos huérfanos',
      () async {
    final cache = CatalogCacheService(backend: _Backend());
    await cache.queueStorageCleanup(['a', 'b', 'a']);
    expect((await cache.storageCleanupQueue()).toSet(), {'a', 'b'});
    await cache.clearStorageCleanup(['a']);
    expect(await cache.storageCleanupQueue(), ['b']);
  });
}
