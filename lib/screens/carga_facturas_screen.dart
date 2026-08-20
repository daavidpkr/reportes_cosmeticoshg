import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/facturas_store.dart';
import '../models/factura.dart';
import '../services/invoice_batch_importer.dart';
import '../services/invoice_file_preparer.dart';
import '../services/supabase_reportes_service.dart';
import '../services/vendedores_store.dart';
import '../theme/hg_theme.dart';

class CargaFacturasScreen extends StatefulWidget {
  const CargaFacturasScreen({super.key, required this.mes, required this.anio});
  final int mes;
  final int anio;
  @override
  State<CargaFacturasScreen> createState() => _CargaFacturasScreenState();
}

class InvoiceIssuesDialog extends StatelessWidget {
  const InvoiceIssuesDialog({super.key, required this.review});
  final InvoiceBatchReview review;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('No hay facturas para importar'),
        content: SizedBox(
          width: 560,
          child: ListView(
            shrinkWrap: true,
            children: [
              ...review.fileIssues.map((e) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.warning_amber),
                  title: Text(e.fileName),
                  subtitle: Text(e.message))),
              ...review.issues.map((e) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.info_outline),
                  title: Text(e.fileName),
                  subtitle: Text(e.message))),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'))
        ],
      );
}

class InvoiceReviewDialog extends StatefulWidget {
  const InvoiceReviewDialog({
    super.key,
    required this.review,
    required this.vendedores,
  });
  final InvoiceBatchReview review;
  final List<Vendedor> vendedores;

  @override
  State<InvoiceReviewDialog> createState() => _InvoiceReviewDialogState();
}

class _InvoiceReviewDialogState extends State<InvoiceReviewDialog> {
  bool _soloPendientes = false;
  bool _guardando = false;
  String? _masivo;

  int get _asignadas => widget.review.invoices
      .where((item) => item.vendedor?.isNotEmpty ?? false)
      .length;

  Future<void> _aplicarATodas(String value) async {
    if (_asignadas > 0) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Reemplazar asignaciones'),
          content: const Text(
              'Ya existen selecciones individuales. ¿Deseas reemplazarlas todas?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Reemplazar')),
          ],
        ),
      );
      if (replace != true) {
        setState(() => _masivo = null);
        return;
      }
    }
    setState(() {
      _masivo = value;
      for (final invoice in widget.review.invoices) {
        invoice.vendedor = value;
      }
    });
  }

  Future<bool> _confirmarDescarte() async {
    if (_asignadas == 0) return true;
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Descartar asignaciones'),
            content: const Text(
                'Las selecciones de vendedor se perderán y no se importará ninguna factura.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Continuar revisando')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Descartar')),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final visibles = widget.review.invoices
        .where((item) => !_soloPendientes || (item.vendedor?.isEmpty ?? true))
        .toList();
    return PopScope(
      canPop: _asignadas == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmarDescarte() && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050, maxHeight: 820),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Revisar y asignar vendedores',
                            style: Theme.of(context).textTheme.headlineSmall),
                        Text(
                            '$_asignadas de ${widget.review.invoices.length} facturas con vendedor'),
                      ])),
                  IconButton(
                      tooltip: 'Cancelar importación',
                      onPressed: () async {
                        if (await _confirmarDescarte() && context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(Icons.close)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                          width: 300,
                          child: DropdownButtonFormField<String>(
                            key: const ValueKey('assign-all-seller'),
                            // ignore: deprecated_member_use
                            value: _masivo,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Asignar vendedor a todas'),
                            items: widget.vendedores
                                .map((v) => DropdownMenuItem(
                                    value: v.etiqueta,
                                    child: Text(v.etiqueta,
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: widget.vendedores.isEmpty
                                ? null
                                : (value) {
                                    if (value != null) _aplicarATodas(value);
                                  },
                          )),
                      FilterChip(
                          label: const Text('Sin vendedor'),
                          selected: _soloPendientes,
                          onSelected: (value) =>
                              setState(() => _soloPendientes = value)),
                    ]),
              ),
              if (widget.vendedores.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                        'No hay vendedores disponibles en el catálogo sincronizado.')),
              const Divider(),
              Expanded(
                  child: ListView.builder(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: visibles.length,
                itemBuilder: (_, index) => _InvoiceReviewCard(
                    invoice: visibles[index],
                    vendedores: widget.vendedores,
                    onChanged: () => setState(() => _masivo = null)),
              )),
              if (widget.review.fileIssues.isNotEmpty ||
                  widget.review.issues.isNotEmpty)
                ExpansionTile(
                    title: Text(
                        '${widget.review.fileIssues.length + widget.review.issues.length} archivo(s) omitido(s)'),
                    children: [
                      ...widget.review.fileIssues.map((e) => ListTile(
                          dense: true,
                          title: Text(e.fileName),
                          subtitle: Text(e.message))),
                      ...widget.review.issues.map((e) => ListTile(
                          dense: true,
                          title: Text(e.fileName),
                          subtitle: Text(e.message))),
                    ]),
              SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton(
                              onPressed: _guardando
                                  ? null
                                  : () async {
                                      if (await _confirmarDescarte() &&
                                          context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    },
                              child: const Text('Cancelar')),
                          FilledButton.icon(
                              key: const ValueKey('confirm-invoice-import'),
                              onPressed: _asignadas !=
                                          widget.review.invoices.length ||
                                      _guardando
                                  ? null
                                  : () {
                                      setState(() => _guardando = true);
                                      Navigator.pop(
                                          context,
                                          widget.review.invoices
                                              .map((item) => FacturaAsignada(
                                                  factura: item.factura,
                                                  vendedor: item.vendedor!))
                                              .toList());
                                    },
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Importar facturas')),
                        ]),
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}

class _InvoiceReviewCard extends StatelessWidget {
  const _InvoiceReviewCard(
      {required this.invoice,
      required this.vendedores,
      required this.onChanged});
  final ReviewableInvoice invoice;
  final List<Vendedor> vendedores;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Card(
        color: invoice.vendedor == null
            ? Theme.of(context)
                .colorScheme
                .errorContainer
                .withValues(alpha: .28)
            : null,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(builder: (_, constraints) {
              final info = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('REF. ${invoice.factura.secuencial}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                        'Factura: ${invoice.factura.secuencial}  ·  ${invoice.factura.fecha}'),
                    Text(invoice.factura.cliente,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (invoice.factura.nombreComercial.isNotEmpty)
                      Text(invoice.factura.nombreComercial,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                        '\$${invoice.factura.total.toStringAsFixed(2)}  ·  ${invoice.file.fromZip ? invoice.file.sourceName : 'XML directo'}'),
                  ]);
              final selector = DropdownButtonFormField<String>(
                key: ValueKey('seller-${invoice.factura.secuencial}'),
                // ignore: deprecated_member_use
                value: invoice.vendedor,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: 'Vendedor obligatorio',
                    suffixIcon: invoice.vendedor == null
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar vendedor',
                            onPressed: () {
                              invoice.vendedor = null;
                              onChanged();
                            },
                            icon: const Icon(Icons.clear))),
                items: vendedores
                    .map((v) => DropdownMenuItem(
                        value: v.etiqueta,
                        child:
                            Text(v.etiqueta, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (value) {
                  invoice.vendedor = value;
                  onChanged();
                },
              );
              return constraints.maxWidth >= 700
                  ? Row(children: [
                      Expanded(child: info),
                      const SizedBox(width: 16),
                      SizedBox(width: 330, child: selector)
                    ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [info, const SizedBox(height: 10), selector]);
            })),
      );
}

class _CargaFacturasScreenState extends State<CargaFacturasScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Carga de facturas')),
        body: CargaFacturasView(mes: widget.mes, anio: widget.anio),
      );
}

class CargaFacturasView extends StatefulWidget {
  const CargaFacturasView(
      {super.key,
      required this.mes,
      required this.anio,
      this.onVolver,
      this.onFacturasGuardadas,
      this.vendedores});
  final int mes;
  final int anio;
  final VoidCallback? onVolver;
  final Future<void> Function()? onFacturasGuardadas;
  final List<Vendedor>? vendedores;
  @override
  State<CargaFacturasView> createState() => _CargaFacturasViewState();
}

class _CargaFacturasViewState extends State<CargaFacturasView> {
  final _store = FacturasStore.instance;
  final _filePreparer = const InvoiceFilePreparer();
  final _batchImporter = const InvoiceBatchImporter();
  SupabaseReportesService? _supabaseReportes;
  bool _cargando = false;
  bool _arrastrando = false;
  List<Vendedor> _vendedores = const [];

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
  }

  Future<void> _cargarCatalogo() async {
    if (widget.vendedores != null) {
      _vendedores = List.unmodifiable(widget.vendedores!);
    } else {
      try {
        final store = VendedoresStore();
        await store.cargar();
        _vendedores = List.unmodifiable(store.vendedores);
      } catch (_) {
        // The application initializes Supabase before reaching this screen.
        // Keeping an empty catalog also makes isolated widget hosts safe.
        _vendedores = const [];
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _seleccionarArchivos() async {
    final resultado = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
      type: FileType.custom,
      allowedExtensions: const ['xml', 'zip'],
    );
    if (resultado == null || !mounted) return;
    await _procesarSeleccionados(resultado.files.map((archivo) async {
      final bytes = archivo.bytes ??
          (archivo.path == null
              ? null
              : await File(archivo.path!).readAsBytes());
      return bytes == null
          ? null
          : SelectedInvoiceFile(name: archivo.name, bytes: bytes);
    }));
  }

  Future<void> _procesarArrastrados(List<DropItem> archivos) async {
    final validos = archivos.where((archivo) {
      final nombre = archivo.name.toLowerCase();
      return nombre.endsWith('.xml') || nombre.endsWith('.zip');
    }).toList();
    await _procesarSeleccionados(
      validos.map((archivo) async => SelectedInvoiceFile(
            name: archivo.name,
            bytes: await archivo.readAsBytes(),
          )),
      ignorados: archivos.length - validos.length,
    );
  }

  Future<void> _procesarSeleccionados(
    Iterable<Future<SelectedInvoiceFile?>> archivos, {
    int ignorados = 0,
  }) async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _arrastrando = false;
    });
    var procesados = 0;
    var rechazados = ignorados;
    var otroMes = 0;
    var duplicados = 0;
    var directos = 0;
    var zips = 0;
    var encontradosEnZip = 0;
    var zipsConError = 0;
    try {
      final seleccionados = <SelectedInvoiceFile>[];
      for (final leer in archivos) {
        try {
          final archivo = await leer;
          if (archivo == null) {
            rechazados++;
          } else {
            seleccionados.add(archivo);
          }
        } catch (_) {
          rechazados++;
        }
      }
      final lote = await _filePreparer.prepare(seleccionados);
      directos = lote.directXmlSelected;
      zips = lote.zipSelected;
      encontradosEnZip = lote.xmlFoundInZips;
      rechazados += lote.issues
          .where((issue) =>
              issue.kind == InvoiceFileIssueKind.unsupported ||
              issue.kind == InvoiceFileIssueKind.tooLarge)
          .length;
      zipsConError = lote.issues
          .where((issue) => issue.kind != InvoiceFileIssueKind.unsupported)
          .length;

      final service = _supabaseReportes ??= SupabaseReportesService();
      final refs = lote.xmlFiles.map((file) {
        try {
          return _store.referenciaDesdeTexto(String.fromCharCodes(file.bytes));
        } catch (_) {
          return null;
        }
      }).whereType<String>();
      final existentes = await service.referenciasExistentesDelReporte(
          refs, widget.anio, widget.mes);
      final revision = _batchImporter.review(lote,
          store: _store, existingReferences: existentes);
      duplicados = revision.issues
          .where((issue) =>
              issue.kind == InvoiceReviewIssueKind.duplicateSelection ||
              issue.kind == InvoiceReviewIssueKind.alreadyExists)
          .length;
      otroMes = revision.issues
          .where((issue) => issue.kind == InvoiceReviewIssueKind.wrongMonth)
          .length;
      rechazados += revision.issues
          .where((issue) => issue.kind == InvoiceReviewIssueKind.invalid)
          .length;
      if (!mounted) return;
      if (revision.invoices.isEmpty) {
        await showDialog<void>(
            context: context,
            builder: (_) => InvoiceIssuesDialog(review: revision));
      } else {
        final asignadas = await showDialog<List<FacturaAsignada>>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              InvoiceReviewDialog(review: revision, vendedores: _vendedores),
        );
        if (asignadas == null) return;
        procesados = await service.importarFacturasMensualesAsignadas(
            asignadas, widget.anio, widget.mes);
        for (final item in asignadas) {
          _store.registrar(item.factura);
        }
        await widget.onFacturasGuardadas?.call();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('No se pudieron guardar las facturas en la nube: $error'),
          backgroundColor: context.hg.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
    if (!mounted) return;
    final detalle = <String>[
      '$directos XML directo(s)',
      '$zips ZIP seleccionado(s)',
      '$encontradosEnZip XML en ZIP',
      if (duplicados > 0) '$duplicados duplicado(s) omitido(s)',
      if (otroMes > 0) '$otroMes de otro mes',
      if (rechazados > 0) '$rechazados no válido(s)',
      if (zipsConError > 0) '$zipsConError ZIP sin XML o con error',
    ];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text('$procesados factura(s) importada(s) · ${detalle.join(' · ')}'),
      backgroundColor: otroMes > 0 ? context.hg.warning : null,
    ));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Carga de facturas',
                style: Theme.of(context).textTheme.headlineSmall),
            const Text(
                'Importa las facturas correspondientes al reporte seleccionado'),
            if (widget.onVolver != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                  onPressed: widget.onVolver,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Volver al reporte de ventas')),
            ],
            const SizedBox(height: 8),
            Expanded(
                child: DropTarget(
              onDragEntered: (_) => setState(() => _arrastrando = true),
              onDragExited: (_) => setState(() => _arrastrando = false),
              onDragDone: (detalle) => _procesarArrastrados(detalle.files),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                    color: _arrastrando ? context.hg.hover : Colors.transparent,
                    border: Border.all(
                        color: _arrastrando
                            ? context.hg.burgundy
                            : Theme.of(context).colorScheme.outline,
                        width: _arrastrando ? 3 : 2),
                    borderRadius: BorderRadius.circular(16)),
                child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.cloud_upload,
                      size: 80, color: context.hg.burgundy),
                  const SizedBox(height: 20),
                  Text(
                      'Facturas de ${widget.mes.toString().padLeft(2, '0')}/${widget.anio}',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  const Text(
                      'Solo se aceptarán facturas XML o ZIP emitidas en este mes. Se guardarán los datos extraídos, no los archivos.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Text(
                      _arrastrando
                          ? 'Suelta aquí los archivos'
                          : 'Arrastra y suelta aquí tus facturas',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: context.hg.burgundy,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text('o selecciónalas manualmente'),
                  const SizedBox(height: 20),
                  if (_cargando)
                    const CircularProgressIndicator()
                  else
                    FilledButton.icon(
                        onPressed: _seleccionarArchivos,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Seleccionar facturas XML o ZIP')),
                  const SizedBox(height: 20),
                  Text('Facturas en memoria: ${_store.cantidad}'),
                ])),
              ),
            )),
          ]),
        ),
      );
}
