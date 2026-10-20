import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../models/catalog.dart';
import '../../services/catalog_cache_service.dart';
import '../../services/catalog_file_error.dart';
import '../../services/catalog_pdf_service.dart';
import '../../services/catalog_repository.dart';
import '../../services/document_download_service.dart';
import '../../theme/hg_theme.dart';
import 'catalog_viewer_screen.dart';

class CatalogsScreen extends StatefulWidget {
  const CatalogsScreen({
    this.repository,
    this.cache,
    this.downloads,
    super.key,
  });

  final CatalogRepository? repository;
  final CatalogCacheService? cache;
  final DocumentDownloadService? downloads;

  @override
  State<CatalogsScreen> createState() => _CatalogsScreenState();
}

class _CatalogsScreenState extends State<CatalogsScreen> {
  static const _pageSize = 12;
  late final CatalogRepository _repository;
  late final CatalogCacheService _cache;
  late final CatalogPdfService _pdfFiles;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final Map<String, Uint8List> _covers = {};
  final Map<String, double> _progress = {};
  final Set<String> _downloaded = {};
  final Set<String> _invalidFiles = {};
  List<Catalog> _catalogs = [];
  CatalogFilter _filter = CatalogFilter.all;
  Timer? _debounce;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SupabaseCatalogRepository();
    _cache = widget.cache ?? CatalogCacheService();
    _pdfFiles = CatalogPdfService(repository: _repository, cache: _cache);
    _scroll.addListener(_onScroll);
    unawaited(_retryCleanup());
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 500 && !_loadingMore && _hasMore) {
      unawaited(_load());
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final offset = reset ? 0 : _catalogs.length;
      final rows = await _repository.list(
        offset: offset,
        limit: _pageSize,
        query: _search.text,
        filter: _filter,
      );
      if (!mounted) return;
      setState(() {
        _catalogs = reset ? rows : [..._catalogs, ...rows];
        _hasMore = rows.length == _pageSize;
        _error = null;
      });
      for (final catalog in rows) {
        if (await _cache.isDownloaded(catalog) && mounted) {
          setState(() => _downloaded.add(catalog.id));
        }
      }
    } catch (error) {
      final cached = reset ? await _cache.cachedCatalogs() : <Catalog>[];
      if (!mounted) return;
      setState(() {
        if (reset && cached.isNotEmpty) {
          _catalogs = cached
              .where((item) =>
                  item.title
                      .toLowerCase()
                      .contains(_search.text.toLowerCase()) &&
                  catalogMatchesFilter(item, _filter))
              .toList();
          _downloaded.addAll(cached.map((item) => item.id));
          _hasMore = false;
          _error = 'Sin conexión: mostrando catálogos descargados.';
        } else {
          _error = 'No se pudieron cargar los catálogos: $error';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 350), () => _load(reset: true));
  }

  Future<Uint8List?> _cover(Catalog catalog) async {
    if (_covers[catalog.id] case final cover?) return cover;
    try {
      final cached = await _cache.cover(catalog);
      if (cached != null) return _covers[catalog.id] = cached;
      if (catalog.coverPath == null) return null;
      return _covers[catalog.id] =
          await _repository.download(catalog.coverPath!);
    } catch (error) {
      logCatalogFileError(CatalogFileStage.cache, error, catalogId: catalog.id);
      return null;
    }
  }

  Future<CachedCatalogFile?> _ensureDownloaded(Catalog catalog) async {
    setState(() => _progress[catalog.id] = 0);
    try {
      final file = await _pdfFiles.obtain(
        catalog,
        onProgress: (value) {
          if (mounted) setState(() => _progress[catalog.id] = value);
        },
        loadCover: () => _cover(catalog),
      );
      if (!mounted) return file;
      setState(() {
        if (file.cachedVersion == catalog.version) {
          _downloaded.add(catalog.id);
          _invalidFiles.remove(catalog.id);
        }
      });
      return file;
    } catch (error) {
      final status = error is CatalogFileException ? error.httpStatus : null;
      final stage = error is CatalogFileException
          ? error.stage
          : CatalogFileStage.httpDownload;
      logCatalogFileError(stage, error,
          httpStatus: status, catalogId: catalog.id);
      if (mounted) {
        if (error is CatalogFileException &&
            (error.stage == CatalogFileStage.validation ||
                error.stage == CatalogFileStage.metadata ||
                error.httpStatus == 404)) {
          setState(() => _invalidFiles.add(catalog.id));
        }
        _message(
          error is CatalogFileException
              ? error.toString()
              : 'No se pudo descargar el PDF. Inténtalo nuevamente.',
          error: true,
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _progress.remove(catalog.id));
    }
  }

  bool _fileActionsEnabled(Catalog catalog) =>
      catalog.canOpen && !_invalidFiles.contains(catalog.id);

  Future<void> _view(Catalog catalog) async {
    final file = await _ensureDownloaded(catalog);
    if (!mounted || file == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CatalogViewerScreen(
        catalog: catalog,
        bytes: file.bytes,
        localPath: file.localPath,
        cachedVersion: file.cachedVersion,
        downloads: widget.downloads,
      ),
    ));
  }

  Future<void> _download(Catalog catalog) async {
    final file = await _ensureDownloaded(catalog);
    if (file == null || !mounted) return;
    if (file.hasNewerVersion) {
      _message(
          'No se pudo descargar la versión ${catalog.version}; se conservó la versión ${file.cachedVersion} sin conexión.',
          error: true);
      return;
    }
    try {
      final saved = await (widget.downloads ?? DocumentDownloadService()).save(
        bytes: file.bytes,
        fileName: safeCatalogFileName(catalog.title, file.cachedVersion),
        mimeType: 'application/pdf',
      );
      if (mounted) _message(saved.confirmationMessage);
    } catch (error) {
      logCatalogFileError(CatalogFileStage.export, error,
          catalogId: catalog.id);
      if (mounted) {
        _message('El navegador no pudo guardar el PDF.', error: true);
      }
    }
  }

  Future<void> _retryCleanup() async {
    final paths = await _cache.storageCleanupQueue();
    if (paths.isEmpty) return;
    try {
      await _repository.removeObjects(paths);
      await _cache.clearStorageCleanup(paths);
    } catch (_) {
      // Se reintentará al abrir nuevamente el módulo.
    }
  }

  Future<void> _edit([Catalog? catalog]) async {
    final input = await showDialog<_CatalogFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CatalogFormDialog(catalog: catalog),
    );
    if (input == null || !mounted) return;
    try {
      if (catalog == null) {
        final draft = await _repository.createDraft(input.title, input.order);
        if (!input.publish) {
          _message('Borrador creado.');
        } else {
          await _publishNew(draft, input);
          _message('Catálogo publicado.');
        }
      } else if (input.pdf == null) {
        await _repository.saveMetadata(catalog,
            title: input.title, order: input.order);
        _message('Cambios guardados.');
      } else {
        await _replaceOrPublish(catalog, input);
        _message(catalog.status == CatalogStatus.borrador
            ? 'Catálogo publicado.'
            : 'Nueva versión publicada.');
      }
      await _load(reset: true);
    } catch (error) {
      if (mounted) {
        _message('No se pudieron guardar los cambios: $error', error: true);
      }
    }
  }

  Future<void> _publishNew(CatalogDraft draft, _CatalogFormResult input) async {
    final uploaded = <String>[];
    try {
      await _repository.upload(draft.filePath, input.pdf!, 'application/pdf');
      uploaded.add(draft.filePath);
      await _repository.upload(draft.coverPath, input.cover!, input.coverMime);
      uploaded.add(draft.coverPath);
      final shell = Catalog(
        id: draft.id,
        organizationId: '',
        title: input.title,
        version: draft.version,
        status: CatalogStatus.borrador,
        active: true,
        featured: false,
        order: input.order,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _repository.publish(
        catalog: shell,
        title: input.title,
        filePath: draft.filePath,
        coverPath: draft.coverPath,
        pageCount: input.pages,
        replaceFile: false,
        order: input.order,
      );
    } catch (error) {
      final state = await _publicationState(draft.id, draft.filePath);
      if (state != true) {
        if (state == false) await _compensate(uploaded);
        throw StateError(state == null
            ? 'No se pudo confirmar la publicación. Los archivos se conservaron para no dañar un posible registro publicado: $error'
            : '$error');
      }
    }
  }

  Future<void> _replaceOrPublish(
      Catalog catalog, _CatalogFormResult input) async {
    if (!input.publish) {
      await _repository.saveMetadata(catalog,
          title: input.title, order: input.order);
      return;
    }
    final nextVersion = catalog.status == CatalogStatus.publicado
        ? catalog.version + 1
        : catalog.version;
    final base = '${catalog.organizationId}/${catalog.id}/v$nextVersion';
    final newFile = '$base/catalogo.pdf';
    final newCover = '$base/portada.webp';
    final uploaded = <String>[];
    try {
      await _repository.upload(newFile, input.pdf!, 'application/pdf');
      uploaded.add(newFile);
      await _repository.upload(newCover, input.cover!, input.coverMime);
      uploaded.add(newCover);
      await _repository.publish(
        catalog: catalog,
        title: input.title,
        filePath: newFile,
        coverPath: newCover,
        pageCount: input.pages,
        replaceFile: catalog.status == CatalogStatus.publicado,
        order: input.order,
      );
    } catch (error) {
      final state = await _publicationState(catalog.id, newFile);
      if (state != true) {
        if (state == false) await _compensate(uploaded);
        throw StateError(state == null
            ? 'No se pudo confirmar la nueva versión. Los archivos se conservaron para no dañar un posible registro publicado: $error'
            : '$error');
      }
    }
    if (catalog.filePath != null || catalog.coverPath != null) {
      final old = [
        if (catalog.filePath != null) catalog.filePath!,
        if (catalog.coverPath != null) catalog.coverPath!
      ];
      try {
        await _repository.removeObjects(old);
      } catch (_) {
        await _cache.queueStorageCleanup(old);
        if (mounted) {
          _message(
              'La nueva versión está activa; la limpieza anterior se reintentará.');
        }
      }
    }
  }

  Future<void> _compensate(List<String> uploaded) async {
    if (uploaded.isEmpty) return;
    try {
      await _repository.removeObjects(uploaded);
    } catch (_) {
      await _cache.queueStorageCleanup(uploaded);
    }
  }

  Future<bool?> _publicationState(String id, String expectedPath) async {
    try {
      return (await _repository.getById(id))?.filePath == expectedPath;
    } catch (_) {
      return null;
    }
  }

  Future<void> _action(Catalog catalog, String action) async {
    try {
      switch (action) {
        case 'edit':
          await _edit(catalog);
          return;
        case 'featured':
          await _repository.setFeatured(catalog.id);
        case 'active':
          await _repository.setActive(catalog.id, !catalog.active);
        case 'delete':
          if (!await _confirmDelete(catalog)) return;
          if (catalog.active) await _repository.setActive(catalog.id, false);
          final paths = [
            if (catalog.filePath != null) catalog.filePath!,
            if (catalog.coverPath != null) catalog.coverPath!
          ];
          final backups = <String, Uint8List>{};
          try {
            for (final path in paths) {
              backups[path] = await _repository.download(path);
            }
            await _repository.removeObjects(paths);
          } catch (error) {
            throw StateError(
                'No se borró el registro porque Storage falló: $error');
          }
          try {
            await _repository.deleteAfterStorage(catalog.id, catalog.version);
          } catch (error) {
            try {
              if (await _repository.getById(catalog.id) == null) {
                await _cache.removeLocal(catalog.id);
                await _load(reset: true);
                return;
              }
            } catch (_) {
              // Ante una respuesta incierta se restauran los objetos para
              // priorizar que un registro existente nunca quede incompleto.
            }
            final restoreFailures = <String>[];
            for (final entry in backups.entries) {
              try {
                await _repository.upload(
                  entry.key,
                  entry.value,
                  entry.key.endsWith('.pdf')
                      ? 'application/pdf'
                      : _imageMime(entry.value),
                );
              } catch (_) {
                restoreFailures.add(entry.key);
              }
            }
            if (restoreFailures.isNotEmpty) {
              throw StateError(
                  'La RPC falló y no fue posible restaurar todos los archivos. '
                  'El catálogo quedó oculto y requiere revisión: $error');
            }
            throw StateError(
                'La RPC falló; los archivos se restauraron y el catálogo quedó oculto: $error');
          }
          await _cache.removeLocal(catalog.id);
      }
      await _load(reset: true);
    } catch (error) {
      if (mounted) _message('$error', error: true);
    }
  }

  Future<bool> _confirmDelete(Catalog catalog) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Eliminar catálogo'),
          content: Text(
              'Se eliminarán los archivos de “${catalog.title}”. Esta acción no se puede deshacer.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar')),
          ],
        ),
      ) ??
      false;

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? context.hg.danger : null,
    ));
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final mobile = constraints.maxWidth < 650;
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: CustomScrollView(
              key: const Key('catalogs-scroll'),
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      mobile ? 16 : 32, 28, mobile ? 16 : 32, 18),
                  sliver: SliverToBoxAdapter(child: _header(mobile)),
                ),
                if (_error != null)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 32),
                    sliver: SliverToBoxAdapter(child: _notice()),
                  ),
                if (_loading)
                  const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()))
                else if (_catalogs.isEmpty)
                  SliverFillRemaining(child: _empty())
                else ...[
                  if (_catalogs.any((item) => item.featured))
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                          mobile ? 16 : 32, 6, mobile ? 16 : 32, 22),
                      sliver: SliverToBoxAdapter(
                          child: _featured(
                              _catalogs.firstWhere((item) => item.featured),
                              mobile)),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                        mobile ? 16 : 32, 0, mobile ? 16 : 32, 28),
                    sliver: mobile
                        ? SliverList.separated(
                            itemCount: _catalogs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, index) =>
                                _card(_catalogs[index], true),
                          )
                        : SliverGrid.builder(
                            itemCount: _catalogs.length,
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 310,
                              mainAxisExtent: 430,
                              mainAxisSpacing: 18,
                              crossAxisSpacing: 18,
                            ),
                            itemBuilder: (_, index) =>
                                _card(_catalogs[index], false),
                          ),
                  ),
                  if (_loadingMore)
                    const SliverToBoxAdapter(
                        child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()))),
                ],
              ],
            ),
          ),
        );
      });

  Widget _header(bool mobile) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Catálogos',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Descubre y consulta nuestras colecciones',
                    style: TextStyle(color: context.hg.mutedText)),
              ])),
          FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(mobile ? 'Añadir' : 'Añadir catálogo')),
        ]),
        const SizedBox(height: 22),
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(
            width: mobile ? double.infinity : 390,
            child: TextField(
              key: const Key('catalog-search'),
              controller: _search,
              onChanged: _searchChanged,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar por título…',
                  border: OutlineInputBorder()),
            ),
          ),
          SegmentedButton<CatalogFilter>(
            segments: const [
              ButtonSegment(value: CatalogFilter.all, label: Text('Todos')),
              ButtonSegment(
                  value: CatalogFilter.newItems, label: Text('Nuevos')),
              ButtonSegment(
                  value: CatalogFilter.updated, label: Text('Actualizados')),
            ],
            selected: {_filter},
            onSelectionChanged: (value) {
              setState(() => _filter = value.single);
              _load(reset: true);
            },
          ),
        ]),
      ]);

  Widget _notice() => Card(
        color: _catalogs.isEmpty
            ? context.hg.warningContainer
            : context.hg.tableHeader,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(_error!)),
            TextButton(
                onPressed: () => _load(reset: true),
                child: const Text('Reintentar')),
          ]),
        ),
      );

  Widget _empty() => Center(
          child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.menu_book_outlined, size: 64, color: context.hg.mutedText),
          const SizedBox(height: 12),
          const Text('No hay catálogos para mostrar.'),
          TextButton(
              onPressed: () => _load(reset: true),
              child: const Text('Reintentar')),
        ]),
      ));

  Widget _featured(Catalog catalog, bool mobile) => Semantics(
        label: 'Catálogo destacado: ${catalog.title}',
        child: Container(
          constraints: BoxConstraints(minHeight: mobile ? 190 : 255),
          decoration: BoxDecoration(
            gradient:
                LinearGradient(colors: [context.hg.burgundy, context.hg.plum]),
            borderRadius: BorderRadius.circular(22),
          ),
          clipBehavior: Clip.antiAlias,
          child: mobile
              ? Row(children: [
                  Expanded(flex: 4, child: _coverWidget(catalog)),
                  Expanded(flex: 6, child: _featuredText(catalog))
                ])
              : Row(children: [
                  Expanded(flex: 4, child: _coverWidget(catalog)),
                  Expanded(flex: 7, child: _featuredText(catalog))
                ]),
        ),
      );

  Widget _featuredText(Catalog catalog) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('DESTACADO',
                  style: TextStyle(
                      color: Color(0xFFF1D487),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 10),
              Text(catalog.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(_catalogMeta(catalog),
                  style: const TextStyle(color: Colors.white70)),
              if (catalog.filePending ||
                  _invalidFiles.contains(catalog.id)) ...[
                const SizedBox(height: 8),
                Text(
                  catalog.filePending
                      ? 'Archivo pendiente de publicación'
                      : 'PDF no disponible',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
              const SizedBox(height: 18),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.tonalIcon(
                    onPressed: _fileActionsEnabled(catalog)
                        ? () => _view(catalog)
                        : null,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Ver')),
                IconButton.filledTonal(
                    tooltip: 'Descargar',
                    onPressed: _fileActionsEnabled(catalog)
                        ? () => _download(catalog)
                        : null,
                    icon: const Icon(Icons.download_outlined)),
              ]),
            ]),
      );

  Widget _card(Catalog catalog, bool mobile) {
    final progress = _progress[catalog.id];
    final content =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: _coverWidget(catalog)),
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 4, children: _badges(catalog)),
          const SizedBox(height: 8),
          Text(catalog.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(_catalogMeta(catalog),
              style: TextStyle(fontSize: 12, color: context.hg.mutedText)),
          if (catalog.filePending || _invalidFiles.contains(catalog.id)) ...[
            const SizedBox(height: 6),
            Text(
                catalog.filePending
                    ? 'Archivo pendiente de publicación'
                    : 'PDF no disponible',
                style: TextStyle(fontSize: 12, color: context.hg.warning)),
          ],
          if (progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            Text('${(progress * 100).round()}%',
                style: const TextStyle(fontSize: 11)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            if (mobile)
              IconButton.filledTonal(
                  tooltip: 'Ver catálogo',
                  onPressed: _fileActionsEnabled(catalog)
                      ? () => _view(catalog)
                      : null,
                  icon: const Icon(Icons.visibility_outlined))
            else
              Expanded(
                  child: FilledButton.tonalIcon(
                      onPressed: _fileActionsEnabled(catalog)
                          ? () => _view(catalog)
                          : null,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Ver'))),
            const SizedBox(width: 8),
            IconButton.outlined(
                tooltip: 'Descargar',
                onPressed: _fileActionsEnabled(catalog)
                    ? () => _download(catalog)
                    : null,
                icon: const Icon(Icons.download_outlined)),
            PopupMenuButton<String>(
              tooltip: 'Administrar catálogo',
              onSelected: (value) => _action(catalog, value),
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar'))),
                if (!catalog.featured &&
                    catalog.status == CatalogStatus.publicado &&
                    catalog.active)
                  const PopupMenuItem(
                      value: 'featured',
                      child: ListTile(
                          leading: Icon(Icons.star_outline),
                          title: Text('Destacar'))),
                PopupMenuItem(
                    value: 'active',
                    child: ListTile(
                        leading: Icon(catalog.active
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        title: Text(catalog.active ? 'Ocultar' : 'Reactivar'))),
                const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Eliminar'))),
              ],
            ),
          ]),
        ]),
      ),
    ]);
    if (!mobile) return Card(clipBehavior: Clip.antiAlias, child: content);
    return SizedBox(
        height: 260,
        child: Card(
            clipBehavior: Clip.antiAlias,
            child: Row(children: [
              SizedBox(width: 110, child: _coverWidget(catalog)),
              Expanded(
                  child: Column(children: content.children.skip(1).toList()))
            ])));
  }

  Widget _coverWidget(Catalog catalog) => FutureBuilder<Uint8List?>(
        future: _cover(catalog),
        builder: (_, snapshot) => snapshot.data == null
            ? ColoredBox(
                color: context.hg.tableHeader,
                child: Center(
                    child: Icon(Icons.auto_stories_outlined,
                        size: 56, color: context.hg.mutedText)))
            : Image.memory(snapshot.data!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) =>
                    const Center(child: Icon(Icons.broken_image_outlined))),
      );

  List<Widget> _badges(Catalog catalog) => [
        if (catalog.isNew)
          _badge('Nuevo', context.hg.positiveContainer, context.hg.positive),
        if (catalog.isUpdated)
          _badge(
              'Actualizado', context.hg.warningContainer, context.hg.warning),
        if (catalog.status == CatalogStatus.borrador)
          _badge('Borrador', context.hg.tableHeader, context.hg.mutedText),
        if (!catalog.active)
          _badge('Oculto', context.hg.tableHeader, context.hg.danger),
        if (_downloaded.contains(catalog.id))
          _badge('Sin conexión', context.hg.positiveContainer,
              context.hg.positive),
      ];

  Widget _badge(String text, Color background, Color foreground) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(99)),
        child: Text(text,
            style: TextStyle(
                color: foreground, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  String _catalogMeta(Catalog catalog) {
    final date =
        catalog.publicUpdatedAt ?? catalog.publishedAt ?? catalog.updatedAt;
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic'
    ];
    final formatted = '${date.day} ${months[date.month - 1]} ${date.year}';
    return '$formatted · v${catalog.version}${catalog.pageCount == null ? '' : ' · ${catalog.pageCount} páginas'}';
  }

  String _imageMime(Uint8List bytes) {
    if (bytes.length > 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'image/jpeg';
    }
    return 'image/png';
  }
}

class _CatalogFormResult {
  const _CatalogFormResult({
    required this.title,
    required this.order,
    required this.publish,
    required this.pages,
    required this.coverMime,
    this.pdf,
    this.cover,
  });
  final String title;
  final int order;
  final bool publish;
  final Uint8List? pdf;
  final Uint8List? cover;
  final int pages;
  final String coverMime;
}

class _CatalogFormDialog extends StatefulWidget {
  const _CatalogFormDialog({this.catalog});
  final Catalog? catalog;
  @override
  State<_CatalogFormDialog> createState() => _CatalogFormDialogState();
}

class _CatalogFormDialogState extends State<_CatalogFormDialog> {
  late final TextEditingController _title;
  late final TextEditingController _order;
  Uint8List? _pdf;
  Uint8List? _cover;
  int _pages = 0;
  String _coverMime = 'image/png';
  bool _publish = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.catalog?.title);
    _order = TextEditingController(text: '${widget.catalog?.order ?? 0}');
    _publish = widget.catalog?.status == CatalogStatus.publicado;
  }

  @override
  void dispose() {
    _title.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true);
    final selectedBytes = result?.files.single.bytes;
    if (selectedBytes == null) return;
    final bytes = Uint8List.fromList(selectedBytes);
    if (bytes.length > 100 * 1024 * 1024) {
      return _setError('El PDF supera el límite de 100 MB.');
    }
    if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      return _setError('El archivo seleccionado no es un PDF válido.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    PdfDocument? document;
    try {
      // PDF.js puede transferir el ArrayBuffer recibido. El visor usa una
      // copia independiente para que los bytes destinados a Storage nunca
      // queden desprendidos o convertidos en un archivo de cero bytes.
      document = await PdfDocument.openData(Uint8List.fromList(bytes));
      final page = await document.getPage(1);
      const width = 720.0;
      final image = await page.render(
          width: width,
          height: width * page.height / page.width,
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF');
      await page.close();
      if (image == null) throw StateError('No se pudo generar la portada.');
      if (!mounted) return;
      setState(() {
        _pdf = Uint8List.fromList(bytes);
        _pages = document!.pagesCount;
        _cover = image.bytes;
        _coverMime = 'image/png';
      });
    } catch (error) {
      _setError('No se pudo leer el PDF: $error');
    } finally {
      await document?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        withData: true);
    final file = result?.files.single;
    if (file?.bytes == null) return;
    final extension = file!.extension?.toLowerCase();
    final mime = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => 'image/png'
    };
    if (!_isImage(file.bytes!, mime)) {
      return _setError(
          'La portada no coincide con un JPEG, PNG o WebP válido.');
    }
    setState(() {
      _cover = file.bytes;
      _coverMime = mime;
      _error = null;
    });
  }

  bool _isImage(Uint8List bytes, String mime) {
    if (mime == 'image/png') {
      return bytes.length > 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47;
    }
    if (mime == 'image/jpeg') {
      return bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    }
    return bytes.length > 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
  }

  void _setError(String text) {
    if (mounted) setState(() => _error = text);
  }

  void _submit() {
    final title = _title.text.trim();
    final order = int.tryParse(_order.text.trim());
    if (title.isEmpty || title.length > 200) {
      return _setError('Ingresa un título de hasta 200 caracteres.');
    }
    if (order == null || order < 0) {
      return _setError('El orden debe ser un entero positivo.');
    }
    final needsPdf =
        _publish && widget.catalog?.status != CatalogStatus.publicado;
    if (needsPdf && (_pdf == null || _cover == null || _pages < 1)) {
      return _setError(
          'Para publicar debes seleccionar un PDF y una portada válida.');
    }
    if (_pdf != null && _cover == null) {
      return _setError('Selecciona o genera una portada.');
    }
    Navigator.pop(
        context,
        _CatalogFormResult(
            title: title,
            order: order,
            publish: _publish,
            pdf: _pdf,
            cover: _cover,
            pages: _pages,
            coverMime: _coverMime));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.catalog == null ? 'Añadir catálogo' : 'Editar catálogo'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _title,
                autofocus: true,
                maxLength: 200,
                decoration: const InputDecoration(
                    labelText: 'Título', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _order,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Orden', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Publicado'),
              subtitle: Text(widget.catalog?.status == CatalogStatus.publicado
                  ? 'Un catálogo publicado no vuelve a borrador; puedes ocultarlo.'
                  : 'Un borrador puede guardarse sin archivos.'),
              value: _publish,
              onChanged: widget.catalog?.status == CatalogStatus.publicado
                  ? null
                  : (value) => setState(() => _publish = value),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: _busy ? null : _pickPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(_pdf == null
                    ? (widget.catalog?.status == CatalogStatus.publicado
                        ? 'Reemplazar PDF'
                        : 'Seleccionar PDF')
                    : 'PDF válido · $_pages páginas')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: _busy ? null : _pickCover,
                icon: const Icon(Icons.image_outlined),
                label: Text(_cover == null
                    ? 'Seleccionar portada (opcional)'
                    : 'Portada lista')),
            if (_busy)
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator()),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: TextStyle(color: context.hg.danger))),
          ])),
        ),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: _busy ? null : _submit, child: const Text('Guardar')),
        ],
      );
}
