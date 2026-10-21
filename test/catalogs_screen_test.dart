import 'dart:async';
import 'dart:typed_data';

import 'package:cosmeticos_hg_reportes/models/catalog.dart';
import 'package:cosmeticos_hg_reportes/screens/catalogs/catalogs_screen.dart';
import 'package:cosmeticos_hg_reportes/services/catalog_cache_backend.dart';
import 'package:cosmeticos_hg_reportes/services/catalog_cache_service.dart';
import 'package:cosmeticos_hg_reportes/services/catalog_repository.dart';
import 'package:cosmeticos_hg_reportes/services/document_download_service.dart';
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
  int downloadCalls = 0;
  final item = Catalog(
    id: 'id',
    organizationId: 'org',
    title: 'Colección profesional',
    filePath: 'org/id/v1/catalogo.pdf',
    version: 1,
    pageCount: 12,
    status: CatalogStatus.publicado,
    active: true,
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
  Future<Uint8List> download(
    String path, {
    void Function(double p1)? onProgress,
    bool requirePdf = false,
  }) async {
    downloadCalls++;
    return Uint8List.fromList('%PDF-1.7\ncontenido'.codeUnits);
  }

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
}

class _Downloads extends DocumentDownloadService {
  int saveCalls = 0;

  @override
  Future<SavedDocument> save({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    saveCalls++;
    return SavedDocument(name: fileName, location: fileName);
  }
}

class _ControlledRepository extends _Repository {
  final listCalls = <({
    String query,
    CatalogFilter filter,
    Completer<List<Catalog>> completer,
  })>[];

  @override
  Future<List<Catalog>> list({
    required int offset,
    required int limit,
    String query = '',
    CatalogFilter filter = CatalogFilter.all,
    bool includeAdministration = true,
  }) {
    final completer = Completer<List<Catalog>>();
    listCalls.add((query: query, filter: filter, completer: completer));
    return completer.future;
  }
}

class _ControlledCoverRepository extends _ControlledRepository {
  final coverDownload = Completer<Uint8List>();

  @override
  Future<Uint8List> download(
    String path, {
    void Function(double p1)? onProgress,
    bool requirePdf = false,
  }) {
    if (path.endsWith('portada.webp')) return coverDownload.future;
    return super.download(
      path,
      onProgress: onProgress,
      requirePdf: requirePdf,
    );
  }
}

Catalog _catalog({
  required String id,
  required String title,
  bool isNew = false,
  int version = 1,
  String? coverPath,
}) =>
    Catalog(
      id: id,
      organizationId: 'org',
      title: title,
      filePath: 'org/$id/v$version/catalogo.pdf',
      coverPath: coverPath,
      version: version,
      pageCount: 1,
      status: CatalogStatus.publicado,
      active: true,
      order: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 10, 20),
      isNew: isNew,
    );

Future<void> _pumpControlled(
  WidgetTester tester,
  _ControlledRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.light().copyWith(
      extensions: const [HgThemeColors.light],
    ),
    home: Scaffold(
      body: CatalogsScreen(
        repository: repository,
        cache: CatalogCacheService(backend: _MemoryBackend()),
      ),
    ),
  ));
  await tester.pump();
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
      expect(find.text('Colección profesional'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('catalog-list-id-v1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('catalog-list-cover-id-v1')),
        findsOneWidget,
      );
      expect(find.text('Destacar'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Descargar reutiliza el PDF versionado de la caché',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Repository();
    final cache = CatalogCacheService(backend: _MemoryBackend());
    final downloads = _Downloads();
    await cache.store(
      repository.item,
      Uint8List.fromList('%PDF-1.7\ncontenido'.codeUnits),
    );
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: const [HgThemeColors.light],
      ),
      home: Scaffold(
        body: CatalogsScreen(
          repository: repository,
          cache: cache,
          downloads: downloads,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Descargar').first);
    await tester.pumpAndSettle();

    expect(repository.downloadCalls, 0);
    expect(downloads.saveCalls, 1);
  });

  testWidgets('elimina una caché corrupta y descarga el PDF una sola vez',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Repository();
    final backend = _MemoryBackend();
    final cache = CatalogCacheService(backend: backend);
    final downloads = _Downloads();
    await cache.store(
      repository.item,
      Uint8List.fromList('%PDF-1.7\ncontenido'.codeUnits),
    );
    backend.data['id/v1/catalogo.pdf'] = Uint8List(0);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: const [HgThemeColors.light],
      ),
      home: Scaffold(
        body: CatalogsScreen(
          repository: repository,
          cache: cache,
          downloads: downloads,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Descargar').first);
    await tester.pumpAndSettle();

    expect(repository.downloadCalls, 1);
    expect(downloads.saveCalls, 1);
    expect(isValidPdfBytes(backend.data['id/v1/catalogo.pdf']!), isTrue);
  });

  testWidgets('cada resultado remoto se muestra una vez en el listado',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ControlledRepository();
    await _pumpControlled(tester, repository);
    final first = _catalog(id: 'first', title: 'Primera colección');
    repository.listCalls.single.completer.complete([
      first,
      _catalog(id: 'regular', title: 'Catálogo regular'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Primera colección'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('catalog-list-first-v1')),
      findsOneWidget,
    );
  });

  testWidgets(
      'la carga inicial muestra todos los resultados de la consulta única',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ControlledRepository();
    await _pumpControlled(tester, repository);
    repository.listCalls.single.completer.complete([
      _catalog(id: 'original', title: 'Catálogo original'),
      _catalog(id: 'new', title: 'Catálogo recién creado'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Catálogo original'), findsOneWidget);
    expect(find.text('Catálogo recién creado'), findsOneWidget);
  });

  testWidgets('una recarga fallida conserva el listado actual y muestra error',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ControlledRepository();
    await _pumpControlled(tester, repository);
    repository.listCalls.single.completer.complete([
      _catalog(id: 'regular', title: 'Listado conservado'),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('catalogs-refresh')));
    await tester.pump();
    repository.listCalls[1].completer.completeError(
      StateError('consulta remota fallida'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Listado conservado'), findsOneWidget);
    expect(
        find.textContaining('Se conserva el último listado'), findsOneWidget);
    expect(find.text('No hay catálogos para mostrar.'), findsNothing);
  });

  testWidgets('una recarga vacía conserva el listado actual', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ControlledRepository();
    await _pumpControlled(tester, repository);
    repository.listCalls.single.completer.complete([
      _catalog(id: 'stable', title: 'Listado estable'),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('catalogs-refresh')));
    await tester.pump();
    repository.listCalls[1].completer.complete(const []);
    await tester.pumpAndSettle();

    expect(find.text('Listado estable'), findsOneWidget);
    expect(find.textContaining('respuesta vacía'), findsOneWidget);
    expect(find.text('No hay catálogos para mostrar.'), findsNothing);
  });

  testWidgets('un error de portada no reemplaza por vacío el listado remoto',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ControlledCoverRepository();
    await _pumpControlled(tester, repository);
    repository.listCalls.single.completer.complete([
      _catalog(
        id: 'cover-error',
        title: 'Catálogo con portada fallida',
        coverPath: 'org/cover-error/v1/portada.webp',
      ),
    ]);
    await tester.pump();

    repository.coverDownload.completeError(StateError('portada no disponible'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('catalog-list-cover-error-v1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('cover-placeholder')), findsOneWidget);
    expect(find.text('Catálogo con portada fallida'), findsOneWidget);
    expect(find.text('Ver'), findsOneWidget);
    expect(find.byTooltip('Descargar'), findsOneWidget);
  });

  test('detecta correctamente MIME de PNG, JPEG y WebP', () {
    expect(
      catalogImageMime(Uint8List.fromList(
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      )),
      'image/png',
    );
    expect(
      catalogImageMime(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
      'image/jpeg',
    );
    expect(
      catalogImageMime(Uint8List.fromList(
        'RIFF1234WEBP'.codeUnits,
      )),
      'image/webp',
    );
    expect(catalogImageMime(Uint8List.fromList([0xFF, 0xD8])), isNull);
  });

  testWidgets('una respuesta del buscador vacía reemplaza el listado',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ControlledRepository();
    await _pumpControlled(tester, repository);
    repository.listCalls.single.completer.complete([
      _catalog(id: 'regular', title: 'Inicial'),
    ]);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('catalog-search')), 'ninguno');
    await tester.pump(const Duration(milliseconds: 351));
    expect(repository.listCalls, hasLength(2));
    await tester.pump(const Duration(seconds: 6));
    repository.listCalls[1].completer.complete(const []);
    await tester.pumpAndSettle();

    expect(find.text('No hay catálogos para mostrar.'), findsOneWidget);
  });

  testWidgets('ignora respuestas de listado fuera de orden', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ControlledRepository();
    await _pumpControlled(tester, repository);
    repository.listCalls.single.completer.complete([
      _catalog(id: 'initial', title: 'Inicial'),
    ]);
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('catalog-search'));
    await tester.enterText(search, 'antigua');
    await tester.pump(const Duration(milliseconds: 351));
    await tester.enterText(search, 'nueva');
    await tester.pump(const Duration(milliseconds: 351));
    expect(repository.listCalls, hasLength(3));

    repository.listCalls[2].completer.complete([
      _catalog(id: 'new', title: 'Respuesta nueva'),
    ]);
    await tester.pump();
    repository.listCalls[1].completer.complete([
      _catalog(id: 'old', title: 'Respuesta antigua'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Respuesta nueva'), findsOneWidget);
    expect(find.text('Respuesta antigua'), findsNothing);
  });

  testWidgets('los filtros sustituyen el alcance del listado', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ControlledRepository();
    await _pumpControlled(tester, repository);
    repository.listCalls.single.completer.complete([
      _catalog(id: 'new-item', title: 'Colección sin filtro'),
      _catalog(id: 'regular', title: 'Regular'),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nuevos'));
    await tester.pump();
    expect(repository.listCalls, hasLength(2));
    expect(repository.listCalls.last.filter, CatalogFilter.newItems);
    repository.listCalls.last.completer.complete(const []);
    await tester.pumpAndSettle();

    expect(find.text('Colección sin filtro'), findsNothing);
    expect(find.text('No hay catálogos para mostrar.'), findsOneWidget);
  });

  testWidgets('una recarga fallida conserva el último listado remoto',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ControlledRepository();
    await _pumpControlled(tester, repository);
    repository.listCalls.single.completer.complete([
      _catalog(id: 'first', title: 'Colección conservada'),
      _catalog(id: 'regular', title: 'Regular'),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('catalogs-refresh')));
    await tester.pump();
    expect(repository.listCalls, hasLength(2));
    repository.listCalls[1].completer
        .completeError(StateError('red no disponible'));
    await tester.pumpAndSettle();

    expect(find.text('Colección conservada'), findsOneWidget);
    expect(find.textContaining('red no disponible'), findsOneWidget);
  });

  testWidgets('ignora respuestas del listado fuera de orden al recargar',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ControlledRepository();
    await _pumpControlled(tester, repository);
    repository.listCalls.single.completer.complete([
      _catalog(id: 'regular', title: 'Regular'),
    ]);
    await tester.pumpAndSettle();

    final refresh = find.byKey(const Key('catalogs-refresh'));
    await tester.tap(refresh);
    await tester.pump();
    await tester.tap(refresh);
    await tester.pump();
    expect(repository.listCalls, hasLength(3));

    repository.listCalls[2].completer.complete([
      _catalog(id: 'new-list', title: 'Lista nueva'),
    ]);
    await tester.pump();
    repository.listCalls[1].completer.complete([
      _catalog(id: 'old-list', title: 'Lista antigua'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Lista nueva'), findsOneWidget);
    expect(find.text('Lista antigua'), findsNothing);
  });
}
