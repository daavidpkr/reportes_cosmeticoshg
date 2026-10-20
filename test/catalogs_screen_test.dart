import 'dart:typed_data';

import 'package:cosmeticos_hg_reportes/models/catalog.dart';
import 'package:cosmeticos_hg_reportes/screens/catalogs/catalogs_screen.dart';
import 'package:cosmeticos_hg_reportes/services/catalog_cache_backend.dart';
import 'package:cosmeticos_hg_reportes/services/catalog_cache_service.dart';
import 'package:cosmeticos_hg_reportes/services/catalog_repository.dart';
import 'package:cosmeticos_hg_reportes/theme/hg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryBackend extends CatalogCacheBackend {
  final data = <String, Uint8List>{};
  @override
  Future<void> delete(String key) async => data.remove(key);
  @override
  Future<String?> localPath(String key) async => null;
  @override
  Future<Uint8List?> read(String key) async => data[key];
  @override
  Future<void> write(String key, Uint8List bytes) async => data[key] = bytes;
}

class _Repository implements CatalogRepository {
  final item = Catalog(
    id: 'id',
    organizationId: 'org',
    title: 'Colección destacada',
    filePath: 'org/id/v1/catalogo.pdf',
    version: 1,
    pageCount: 12,
    status: CatalogStatus.publicado,
    active: true,
    featured: true,
    order: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026, 10, 19),
    isNew: true,
  );

  @override
  Future<Catalog?> getById(String id) async => item;
  @override
  Future<List<Catalog>> list(
          {required int offset,
          required int limit,
          String query = '',
          CatalogFilter filter = CatalogFilter.all,
          bool includeAdministration = true}) async =>
      offset == 0 ? [item] : [];
  @override
  Future<Uint8List> download(String path,
          {void Function(double p1)? onProgress}) async =>
      Uint8List.fromList([1]);
  @override
  Future<void> removeObjects(Iterable<String> paths) async {}
  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {}
  @override
  Future<CatalogDraft> createDraft(String title, int order) =>
      throw UnimplementedError();
  @override
  Future<void> deleteAfterStorage(String id, int expectedVersion) =>
      throw UnimplementedError();
  @override
  Future<Catalog> publish(
          {required Catalog catalog,
          required String title,
          required String filePath,
          required String coverPath,
          required int pageCount,
          required bool replaceFile,
          required int order}) =>
      throw UnimplementedError();
  @override
  Future<Catalog> saveMetadata(Catalog catalog,
          {required String title, required int order}) =>
      throw UnimplementedError();
  @override
  Future<Catalog> setActive(String id, bool active) =>
      throw UnimplementedError();
  @override
  Future<Catalog> setFeatured(String id) => throw UnimplementedError();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(360, 760), const Size(1280, 900)]) {
    testWidgets('catálogos responde sin overflow en ${size.width}',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme:
            ThemeData.light().copyWith(extensions: const [HgThemeColors.light]),
        home: Scaffold(
          body: CatalogsScreen(
            repository: _Repository(),
            cache: CatalogCacheService(backend: _MemoryBackend()),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Catálogos'), findsOneWidget);
      expect(find.byKey(const Key('catalog-search')), findsOneWidget);
      expect(find.text('Colección destacada'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
