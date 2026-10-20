import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/catalog.dart';
import '../../services/catalog_external_open.dart';
import '../../services/document_download_service.dart';
import '../../theme/hg_theme.dart';

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
  late final PdfControllerPinch _pdfController;
  late final TextEditingController _pageController;
  int _page = 1;
  int _pages = 0;

  @override
  void initState() {
    super.initState();
    _pdfController =
        PdfControllerPinch(document: PdfDocument.openData(widget.bytes));
    _pageController = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pdfController.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    try {
      final saved = await (widget.downloads ?? DocumentDownloadService()).save(
        bytes: widget.bytes,
        fileName: safeCatalogFileName(widget.catalog.title,
            widget.cachedVersion ?? widget.catalog.version),
        mimeType: 'application/pdf',
      );
      if (mounted) _message(saved.confirmationMessage);
    } catch (error) {
      if (mounted) _message('No se pudo guardar: $error', error: true);
    }
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(
        title: widget.catalog.title,
        files: [XFile.fromData(widget.bytes, mimeType: 'application/pdf')],
        fileNameOverrides: [
          safeCatalogFileName(widget.catalog.title,
              widget.cachedVersion ?? widget.catalog.version)
        ],
      ));
    } catch (error) {
      if (mounted) _message('No se pudo compartir: $error', error: true);
    }
  }

  Future<void> _openExternal() async {
    try {
      await openCatalogExternally(widget.bytes, widget.localPath);
    } catch (error) {
      if (mounted) _message('$error', error: true);
    }
  }

  void _message(String text, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? context.hg.danger : null,
      ));

  void _goToPage() {
    final value = int.tryParse(_pageController.text);
    if (value == null || value < 1 || value > _pages) {
      _message('Ingresa una página entre 1 y $_pages.', error: true);
      return;
    }
    _pdfController.animateToPage(
        pageNumber: value,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut);
  }

  void _zoom(double factor) {
    final current = _pdfController.zoomRatio;
    final target = (current * factor).clamp(1.0, 6.0);
    final change = target / current;
    _pdfController.value = _pdfController.value.clone()
      ..scaleByDouble(change, change, change, 1);
  }

  void _resetZoom() => _pdfController.animateToPage(
      pageNumber: _page,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final oldVersion = widget.cachedVersion != null &&
        widget.cachedVersion! < widget.catalog.version;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.catalog.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              tooltip: 'Descargar',
              onPressed: _download,
              icon: const Icon(Icons.download_outlined)),
          IconButton(
              tooltip: 'Compartir',
              onPressed: _share,
              icon: const Icon(Icons.share_outlined)),
          IconButton(
              tooltip: 'Abrir con otra aplicación',
              onPressed: _openExternal,
              icon: const Icon(Icons.open_in_new)),
        ],
      ),
      body: Column(children: [
        if (oldVersion)
          MaterialBanner(
            content: Text(
                'Estás viendo la versión ${widget.cachedVersion}. La versión ${widget.catalog.version} está disponible.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ACTUALIZAR'))
            ],
          ),
        Expanded(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: PdfViewPinch(
              controller: _pdfController,
              scrollDirection: Axis.vertical,
              minScale: 1,
              maxScale: 6,
              onDocumentLoaded: (document) =>
                  setState(() => _pages = document.pagesCount),
              onPageChanged: (page) => setState(() {
                _page = page;
                _pageController.text = '$page';
              }),
              builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                options: const DefaultBuilderOptions(),
                documentLoaderBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
                pageLoaderBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
                errorBuilder: (_, error) =>
                    Center(child: Text('No se pudo mostrar el PDF: $error')),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Página anterior',
                    onPressed: _page > 1
                        ? () => _pdfController.previousPage(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _pageController,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          isDense: true, border: OutlineInputBorder()),
                      onSubmitted: (_) => _goToPage(),
                    ),
                  ),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('de ${_pages == 0 ? '…' : _pages}')),
                  IconButton(
                    tooltip: 'Página siguiente',
                    onPressed: _pages > 0 && _page < _pages
                        ? () => _pdfController.nextPage(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                      tooltip: 'Alejar',
                      onPressed: () => _zoom(.8),
                      icon: const Icon(Icons.zoom_out)),
                  IconButton(
                      tooltip: 'Restablecer zoom',
                      onPressed: _resetZoom,
                      icon: const Icon(Icons.fit_screen_outlined)),
                  IconButton(
                      tooltip: 'Acercar',
                      onPressed: () => _zoom(1.25),
                      icon: const Icon(Icons.zoom_in)),
                ]),
          ),
        ),
      ]),
    );
  }
}
