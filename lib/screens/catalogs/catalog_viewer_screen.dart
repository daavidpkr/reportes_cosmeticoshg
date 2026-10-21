import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/catalog.dart';
import '../../services/catalog_external_open.dart';
import '../../services/catalog_file_error.dart';
import '../../services/document_download_service.dart';
import '../../theme/hg_theme.dart';

bool usesPinchCatalogViewer(TargetPlatform platform, {required bool isWeb}) =>
    isWeb || platform != TargetPlatform.windows;

class CatalogViewerScreen extends StatefulWidget {
  const CatalogViewerScreen({
    required this.catalog,
    required this.bytes,
    this.localPath,
    this.cachedVersion,
    this.downloads,
    super.key,
  });

  final Catalog catalog;
  final Uint8List bytes;
  final String? localPath;
  final int? cachedVersion;
  final DocumentDownloadService? downloads;

  @override
  State<CatalogViewerScreen> createState() => _CatalogViewerScreenState();
}

class _CatalogViewerScreenState extends State<CatalogViewerScreen> {
  PdfControllerPinch? _pinchController;
  PdfController? _simpleController;
  late final TextEditingController _pageController;
  String? _startupError;
  int _page = 1;
  int _pages = 0;
  bool _fullScreen = false;

  @override
  void initState() {
    super.initState();
    if (!isValidPdfBytes(widget.bytes)) {
      _startupError = 'El archivo recibido está vacío o no comienza con %PDF-.';
    } else {
      final document = PdfDocument.openData(Uint8List.fromList(widget.bytes));
      if (usesPinchCatalogViewer(defaultTargetPlatform, isWeb: kIsWeb)) {
        _pinchController = PdfControllerPinch(document: document);
      } else {
        _simpleController = PdfController(document: document);
      }
    }
    _pageController = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    if (_fullScreen &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
      );
    }
    _pageController.dispose();
    _pinchController?.dispose();
    _simpleController?.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    await _withValidPdf(
      action: (bytes) async {
        final saved =
            await (widget.downloads ?? DocumentDownloadService()).save(
          bytes: bytes,
          fileName: safeCatalogFileName(widget.catalog.title,
              widget.cachedVersion ?? widget.catalog.version),
          mimeType: 'application/pdf',
        );
        if (mounted) _message(saved.confirmationMessage);
      },
      failureMessage: 'No se pudo guardar el PDF.',
    );
  }

  Future<void> _share() async {
    await _withValidPdf(
      action: (bytes) => SharePlus.instance.share(ShareParams(
        title: widget.catalog.title,
        files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
        fileNameOverrides: [
          safeCatalogFileName(widget.catalog.title,
              widget.cachedVersion ?? widget.catalog.version)
        ],
      )),
      failureMessage: 'No se pudo compartir el PDF.',
    );
  }

  Future<void> _openExternal() async {
    await _withValidPdf(
      action: (bytes) => openCatalogExternally(bytes, widget.localPath),
      failureMessage: 'No se pudo abrir el PDF con otra aplicación.',
    );
  }

  Future<void> _withValidPdf({
    required Future<void> Function(Uint8List bytes) action,
    required String failureMessage,
  }) async {
    try {
      if (!isValidPdfBytes(widget.bytes)) {
        throw const CatalogFileException(
          stage: CatalogFileStage.validation,
          userMessage: 'El PDF está vacío o no contiene una cabecera válida.',
        );
      }
      await action(Uint8List.fromList(widget.bytes));
    } catch (error) {
      _actionError(
        error is CatalogFileException ? error.stage : CatalogFileStage.export,
        error,
        error is CatalogFileException ? error.userMessage : failureMessage,
      );
    }
  }

  void _message(String text, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? context.hg.danger : null,
      ));

  void _actionError(CatalogFileStage stage, Object error, String userMessage) {
    logCatalogFileError(stage, error, catalogId: widget.catalog.id);
    if (mounted) _message(userMessage, error: true);
  }

  void _goToPage() {
    final value = int.tryParse(_pageController.text);
    if (value == null || value < 1 || value > _pages) {
      _message('Ingresa una página entre 1 y $_pages.', error: true);
      return;
    }
    _animateToPage(value);
  }

  void _zoom(double factor) {
    final controller = _pinchController;
    if (controller == null) return;
    final current = controller.zoomRatio;
    final target = (current * factor).clamp(1.0, 6.0);
    final change = target / current;
    controller.value = controller.value.clone()
      ..scaleByDouble(change, change, change, 1);
  }

  void _resetZoom() => _animateToPage(_page);

  Future<void> _animateToPage(int page) => _pinchController != null
      ? _pinchController!.animateToPage(
          pageNumber: page,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        )
      : _simpleController!.animateToPage(
          page,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );

  Future<void> _previousPage() => _pinchController != null
      ? _pinchController!.previousPage(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        )
      : _simpleController!.previousPage(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );

  Future<void> _nextPage() => _pinchController != null
      ? _pinchController!.nextPage(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        )
      : _simpleController!.nextPage(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );

  void _documentLoaded(PdfDocument document) {
    if (mounted) setState(() => _pages = document.pagesCount);
  }

  void _pageChanged(int page) {
    if (!mounted) return;
    setState(() {
      _page = page;
      _pageController.text = '$page';
    });
  }

  void _documentError(Object error) {
    logCatalogFileError(CatalogFileStage.viewer, error,
        catalogId: widget.catalog.id);
  }

  void _setFullScreen(bool value) {
    if (_fullScreen == value) return;
    setState(() => _fullScreen = value);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(SystemChrome.setEnabledSystemUIMode(
        value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ));
    }
  }

  void _handleBack(bool didPop) {
    if (!didPop && _fullScreen) _setFullScreen(false);
  }

  Widget _pdfViewer() {
    if (_startupError case final error?) {
      return Center(child: Text('No se pudo mostrar el PDF: $error'));
    }
    final pinch = _pinchController;
    if (pinch != null) {
      return PdfViewPinch(
        controller: pinch,
        scrollDirection: Axis.vertical,
        minScale: 1,
        maxScale: 6,
        onDocumentLoaded: _documentLoaded,
        onDocumentError: _documentError,
        onPageChanged: _pageChanged,
        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          pageLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, error) => Center(
            child: Text(
              'No se pudo mostrar el PDF validado: ${sanitizeCatalogError(error)}',
            ),
          ),
        ),
      );
    }
    final simple = _simpleController;
    if (simple == null) {
      return const Center(child: Text('No se pudo iniciar el visor PDF.'));
    }
    return PdfView(
      controller: simple,
      scrollDirection: Axis.horizontal,
      onDocumentLoaded: _documentLoaded,
      onDocumentError: _documentError,
      onPageChanged: _pageChanged,
      builders: PdfViewBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        documentLoaderBuilder: (_) =>
            const Center(child: CircularProgressIndicator()),
        pageLoaderBuilder: (_) =>
            const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Center(
          child: Text(
            'No se pudo mostrar el PDF validado: ${sanitizeCatalogError(error)}',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final oldVersion = widget.cachedVersion != null &&
        widget.cachedVersion! < widget.catalog.version;
    return PopScope(
      canPop: !_fullScreen,
      onPopInvokedWithResult: (didPop, _) => _handleBack(didPop),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_fullScreen) _setFullScreen(false);
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: _fullScreen
                ? null
                : AppBar(
                    title: Text(
                      widget.catalog.title,
                      overflow: TextOverflow.ellipsis,
                    ),
                    actions: [
                      IconButton(
                        key: const Key('viewer-enter-fullscreen'),
                        tooltip: 'Pantalla completa',
                        onPressed: () => _setFullScreen(true),
                        icon: const Icon(Icons.fullscreen),
                      ),
                      IconButton(
                        tooltip: 'Descargar',
                        onPressed: _startupError == null ? _download : null,
                        icon: const Icon(Icons.download_outlined),
                      ),
                      IconButton(
                        tooltip: 'Compartir',
                        onPressed: _startupError == null ? _share : null,
                        icon: const Icon(Icons.share_outlined),
                      ),
                      IconButton(
                        tooltip: 'Abrir con otra aplicación',
                        onPressed: _startupError == null ? _openExternal : null,
                        icon: const Icon(Icons.open_in_new),
                      ),
                    ],
                  ),
            body: Stack(
              children: [
                Column(
                  children: [
                    Visibility(
                      visible: !_fullScreen && oldVersion,
                      maintainState: true,
                      child: MaterialBanner(
                        content: Text(
                          'Estás viendo la versión ${widget.cachedVersion}. '
                          'La versión ${widget.catalog.version} está disponible.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('ACTUALIZAR'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ColoredBox(
                        key: const Key('viewer-pdf-surface'),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: _pdfViewer(),
                      ),
                    ),
                    Visibility(
                      visible: !_fullScreen,
                      maintainState: true,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              IconButton(
                                tooltip: 'Página anterior',
                                onPressed: _page > 1 ? _previousPage : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              SizedBox(
                                width: 60,
                                child: TextField(
                                  controller: _pageController,
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) => _goToPage(),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text('de ${_pages == 0 ? '…' : _pages}'),
                              ),
                              IconButton(
                                tooltip: 'Página siguiente',
                                onPressed: _pages > 0 && _page < _pages
                                    ? _nextPage
                                    : null,
                                icon: const Icon(Icons.chevron_right),
                              ),
                              const SizedBox(width: 8),
                              if (_pinchController != null) ...[
                                IconButton(
                                  tooltip: 'Alejar',
                                  onPressed: () => _zoom(.8),
                                  icon: const Icon(Icons.zoom_out),
                                ),
                                IconButton(
                                  tooltip: 'Restablecer zoom',
                                  onPressed: _resetZoom,
                                  icon: const Icon(Icons.fit_screen_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Acercar',
                                  onPressed: () => _zoom(1.25),
                                  icon: const Icon(Icons.zoom_in),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_fullScreen)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: SafeArea(
                      child: FloatingActionButton.small(
                        key: const Key('viewer-exit-fullscreen'),
                        tooltip: 'Salir de pantalla completa',
                        onPressed: () => _setFullScreen(false),
                        child: const Icon(Icons.fullscreen_exit),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
