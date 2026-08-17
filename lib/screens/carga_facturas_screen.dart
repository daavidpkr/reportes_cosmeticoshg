import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/facturas_store.dart';
import '../services/supabase_reportes_service.dart';
import '../theme/hg_theme.dart';

class CargaFacturasScreen extends StatefulWidget {
  const CargaFacturasScreen({super.key, required this.mes, required this.anio});

  final int mes;
  final int anio;

  @override
  State<CargaFacturasScreen> createState() => _CargaFacturasScreenState();
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
      this.onFacturasGuardadas});
  final int mes;
  final int anio;
  final VoidCallback? onVolver;
  final Future<void> Function()? onFacturasGuardadas;
  @override
  State<CargaFacturasView> createState() => _CargaFacturasViewState();
}

class _CargaFacturasViewState extends State<CargaFacturasView> {
  final _store = FacturasStore.instance;
  SupabaseReportesService? _supabaseReportes;
  bool _cargando = false;
  bool _arrastrando = false;

  Future<void> _seleccionarArchivos() async {
    final resultado = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
      type: FileType.custom,
      allowedExtensions: const ['xml', 'html', 'htm'],
    );
    if (resultado == null || !mounted) return;

    await _procesarContenidos(
      resultado.files.map((archivo) async {
        if (kIsWeb) return archivo.bytes;
        final ruta = archivo.path;
        return ruta == null ? null : File(ruta).readAsBytes();
      }),
    );
  }

  Future<void> _procesarArrastrados(List<DropItem> archivos) async {
    final validos = archivos.where((archivo) {
      final nombre = archivo.name.toLowerCase();
      return nombre.endsWith('.xml') ||
          nombre.endsWith('.html') ||
          nombre.endsWith('.htm');
    }).toList();
    await _procesarContenidos(
      validos.map((archivo) async => archivo.readAsBytes()),
      ignorados: archivos.length - validos.length,
    );
  }

  Future<void> _procesarContenidos(
    Iterable<Future<List<int>?>> contenidos, {
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
    try {
      for (final leer in contenidos) {
        try {
          final bytes = await leer;
          if (bytes == null) {
            rechazados++;
            continue;
          }
          final contenido = utf8.decode(bytes, allowMalformed: true);
          switch (_store.agregarDesdeTexto(contenido)) {
            case ResultadoFactura.agregada:
              procesados++;
            case ResultadoFactura.mesIncorrecto:
              otroMes++;
            case ResultadoFactura.invalida:
              rechazados++;
          }
        } catch (_) {
          rechazados++;
        }
      }
      if (procesados > 0) {
        await (_supabaseReportes ??= SupabaseReportesService())
            .importarFacturasMensuales(
                _store.facturas, widget.anio, widget.mes);
        await widget.onFacturasGuardadas?.call();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudieron guardar las facturas en la nube: $error',
            ),
            backgroundColor: context.hg.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
    if (!mounted) return;
    final errores = [
      if (otroMes > 0) '$otroMes de otro mes',
      if (rechazados > 0) '$rechazados no válidos',
    ];
    final detalle = errores.isEmpty ? '' : ' · ${errores.join(' · ')}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$procesados archivo(s) procesado(s)$detalle'),
        backgroundColor: otroMes > 0 ? context.hg.warning : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Carga de facturas',
              style: Theme.of(context).textTheme.headlineSmall),
          const Text(
              'Importa las facturas correspondientes al reporte seleccionado'),
          if (widget.onVolver != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: widget.onVolver,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver al reporte de ventas'),
            ),
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
                  width: _arrastrando ? 3 : 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_upload,
                      size: 80,
                      color: context.hg.burgundy,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Facturas de ${widget.mes.toString().padLeft(2, '0')}/${widget.anio}',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Solo se aceptarán facturas emitidas en este mes. Se guardarán los datos extraídos, no los archivos.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _arrastrando
                          ? 'Suelta aquí los archivos'
                          : 'Arrastra y suelta aquí tus facturas',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: context.hg.burgundy,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 10),
                    const Text('o selecciónalas manualmente'),
                    const SizedBox(height: 20),
                    if (_cargando)
                      const CircularProgressIndicator()
                    else
                      FilledButton.icon(
                        onPressed: _seleccionarArchivos,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Seleccionar facturas'),
                      ),
                    const SizedBox(height: 20),
                    Text('Facturas en memoria: ${_store.cantidad}'),
                  ],
                ),
              ),
            ),
          )),
        ]),
      ),
    );
  }
}
