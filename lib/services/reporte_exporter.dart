import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/fila_venta.dart';
import 'web_download_stub.dart'
    if (dart.library.js_interop) 'web_download.dart';

class ReporteExporter {
  Future<String> guardar(
    List<FilaVenta> filas, {
    String? vendedor,
    Map<String, String> nombresVendedores = const {},
    String? periodo,
  }) async {
    final seleccionadas = vendedor == null
        ? filas
        : filas.where((fila) => fila.vendedor == vendedor).toList();
    final sufijo = vendedor == null
        ? 'general'
        : vendedor.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final periodoArchivo = periodo == null
        ? ''
        : '_${periodo.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
    final nombreArchivo = 'reporte_ventas_$sufijo$periodoArchivo.pdf';
    final bytes = await _generarPdf(
      seleccionadas,
      vendedor: vendedor,
      nombresVendedores: nombresVendedores,
      periodo: periodo,
    );

    if (kIsWeb) {
      descargarArchivoWeb(bytes, nombreArchivo);
      return nombreArchivo;
    }

    final directorio = await getApplicationDocumentsDirectory();
    final archivo = File(
      '${directorio.path}${Platform.pathSeparator}$nombreArchivo',
    );
    await archivo.writeAsBytes(bytes, flush: true);
    return archivo.path;
  }

  Future<String> guardarResumenMensual(
    List<FilaVenta> filas, {
    required String periodo,
    Map<String, String> nombresVendedores = const {},
  }) async {
    final periodoArchivo = periodo
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final nombreArchivo = 'resumen_mensual_$periodoArchivo.pdf';
    final bytes = await _generarResumenMensualPdf(
      filas.where((fila) => fila.tieneDatos).toList(),
      periodo: periodo,
      nombresVendedores: nombresVendedores,
    );

    if (kIsWeb) {
      descargarArchivoWeb(bytes, nombreArchivo);
      return nombreArchivo;
    }

    final directorio = await getApplicationDocumentsDirectory();
    final archivo = File(
      '${directorio.path}${Platform.pathSeparator}$nombreArchivo',
    );
    await archivo.writeAsBytes(bytes, flush: true);
    return archivo.path;
  }

  Future<Uint8List> _generarResumenMensualPdf(
    List<FilaVenta> filas, {
    required String periodo,
    required Map<String, String> nombresVendedores,
  }) async {
    final documento = pw.Document(
      title: 'Resumen mensual - Cosméticos HG - $periodo',
      author: 'Cosméticos HG',
    );
    final rosa = PdfColor.fromHex('#B71157');
    final filasValidas = filas.where((fila) => !fila.anulada).toList();
    final ventas = filasValidas.fold(0.0, (suma, fila) => suma + fila.venta);
    final cobros =
        filasValidas.fold(0.0, (suma, fila) => suma + fila.totalAbonos);
    final saldo = filasValidas.fold(0.0, (suma, fila) => suma + fila.saldo);
    final esmaltes = filasValidas.fold(0, (suma, fila) => suma + fila.esmalte);
    final pagadas = filas.where((fila) => fila.pagada).length;
    final pendientes = filas.length - pagadas;

    final porVendedor = <String, _ResumenVendedorPdf>{};
    for (final fila in filas) {
      final clave = fila.vendedor.trim();
      final nombre =
          clave.isEmpty ? 'Sin vendedor' : nombresVendedores[clave] ?? clave;
      final resumen = porVendedor.putIfAbsent(
        nombre,
        () => _ResumenVendedorPdf(nombre),
      );
      resumen.facturas += 1;
      if (!fila.anulada) {
        resumen.esmaltes += fila.esmalte;
        resumen.ventas += fila.venta;
        resumen.cobros += fila.totalAbonos;
        resumen.saldo += fila.saldo;
      }
    }
    final vendedores = porVendedor.values.toList()
      ..sort((a, b) => b.ventas.compareTo(a.ventas));
    final porcentajeCobrado = ventas == 0 ? 0.0 : cobros / ventas * 100;
    final descripcion = filas.isEmpty
        ? 'No se registraron ventas durante $periodo.'
        : 'Durante $periodo se registraron ${filas.length} facturas por '
            '${_dinero(ventas)}. Se cobraron ${_dinero(cobros)} '
            '(${porcentajeCobrado.toStringAsFixed(1)} % de las ventas) y quedó '
            'un saldo de ${_dinero(saldo)}. Se vendieron $esmaltes esmaltes; '
            '$pagadas facturas quedaron pagadas y $pendientes pendientes.';

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) =>
            _encabezado('REPORTE MENSUAL DE ESTADÍSTICAS - $periodo', rosa),
        footer: _piePagina,
        build: (_) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey400, width: .5),
            ),
            child:
                pw.Text(descripcion, style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.SizedBox(height: 18),
          pw.Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _total('Facturas', filas.length.toDouble()),
              _total('Esmaltes', esmaltes.toDouble()),
              _total('Ventas', ventas, dinero: true),
              _total('Cobros', cobros, dinero: true),
              _total('Por cobrar', saldo, dinero: true),
            ],
          ),
          pw.SizedBox(height: 22),
          pw.Text(
            'RESULTADOS POR VENDEDOR',
            style: pw.TextStyle(
              color: rosa,
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const [
              'VENDEDOR',
              'FACTURAS',
              'ESMALTES',
              'VENTAS',
              'COBROS',
              'POR COBRAR',
            ],
            data: vendedores
                .map((vendedor) => [
                      vendedor.nombre,
                      vendedor.facturas,
                      vendedor.esmaltes,
                      _dinero(vendedor.ventas),
                      _dinero(vendedor.cobros),
                      _dinero(vendedor.saldo),
                    ])
                .toList(),
            headerDecoration: pw.BoxDecoration(color: rosa),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
        ],
      ),
    );
    return documento.save();
  }

  Future<Uint8List> _generarPdf(
    List<FilaVenta> filas, {
    String? vendedor,
    Map<String, String> nombresVendedores = const {},
    String? periodo,
  }) async {
    final documento = pw.Document(
      title: 'Reporte de ventas - Cosméticos HG',
      author: 'Cosméticos HG',
    );
    final filasConDatos = filas.where((fila) => fila.tieneDatos).toList();
    final comentarios = _obtenerComentarios(filasConDatos);
    final rosa = PdfColor.fromHex('#B71157');
    // Equivale a Colors.green (#4CAF50) con 12 % de opacidad sobre blanco,
    // que es el color usado para las filas pagadas en la tabla de la app.
    final verdePagada = PdfColor.fromHex('#DCEEDC');
    // Equivale al rojo de peligro con 12 % de opacidad sobre blanco.
    final rojoAnulada = PdfColor.fromHex('#F4E7EA');

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        header: (_) => _encabezado(
          '${vendedor == null ? 'REPORTE GENERAL DE VENTAS' : 'REPORTE DE VENTAS - ${nombresVendedores[vendedor] ?? vendedor}'}${periodo == null ? '' : ' - $periodo'}',
          rosa,
        ),
        footer: _piePagina,
        build: (_) => [
          pw.TableHelper.fromTextArray(
            columnWidths: const {
              0: pw.FlexColumnWidth(.55),
              1: pw.FlexColumnWidth(.65),
              2: pw.FlexColumnWidth(3.5),
              3: pw.FlexColumnWidth(2.55),
              4: pw.FlexColumnWidth(1.25),
              5: pw.FlexColumnWidth(1.25),
              6: pw.FlexColumnWidth(1.45),
              7: pw.FlexColumnWidth(1.3),
              8: pw.FlexColumnWidth(.9),
              9: pw.FlexColumnWidth(1.50),
              10: pw.FlexColumnWidth(1.1),
              11: pw.FlexColumnWidth(1),
            },
            headers: const [
              'NRO',
              'REF.',
              'CLIENTE',
              'NOMBRE COMERCIAL',
              'FECHA',
              'NRO. FACT.',
              'VENDEDOR',
              'ESMALTE',
              'VENTA',
              'ABONOS',
              'TOT. ABONO',
              'SALDO',
            ],
            data: filasConDatos
                .map(
                  (fila) => [
                    fila.numero,
                    _referenciaParaPdf(fila.referencia),
                    fila.cliente,
                    fila.nombreComercial,
                    fila.fecha,
                    fila.numeroFactura,
                    nombresVendedores[fila.vendedor] ?? fila.vendedor,
                    fila.esmalte,
                    fila.anulada ? 'ANULADA' : _dinero(fila.venta),
                    fila.abonos
                        .asMap()
                        .entries
                        .where((item) => item.value.valor != 0)
                        .map(
                          (item) =>
                              '${item.key + 1}: ${_dinero(item.value.valor)}',
                        )
                        .join(' / '),
                    fila.anulada ? 'ANULADA' : _dinero(fila.totalAbonos),
                    fila.anulada ? 'ANULADA' : _dinero(fila.saldo),
                  ],
                )
                .toList(),
            headerDecoration: pw.BoxDecoration(color: rosa),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 7,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 3,
              vertical: 2.5,
            ),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            cellDecoration: (_, __, rowNum) {
              final indiceFila = rowNum - 1;
              if (indiceFila >= 0 && indiceFila < filasConDatos.length) {
                final fila = filasConDatos[indiceFila];
                if (fila.anulada) {
                  return pw.BoxDecoration(color: rojoAnulada);
                }
                if (fila.pagada) {
                  return pw.BoxDecoration(color: verdePagada);
                }
              }
              return const pw.BoxDecoration();
            },
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              _total(
                'Total esmaltes',
                filas
                    .where((fila) => !fila.anulada)
                    .fold(0, (suma, fila) => suma + fila.esmalte)
                    .toDouble(),
              ),
              pw.SizedBox(width: 24),
              _total(
                'Total ventas',
                filas
                    .where((fila) => !fila.anulada)
                    .fold(0.0, (suma, fila) => suma + fila.venta),
                dinero: true,
              ),
              pw.SizedBox(width: 24),
              _total(
                'Total cobros',
                filas.where((fila) => !fila.anulada).fold(
                      0.0,
                      (suma, fila) => suma + fila.totalAbonos,
                    ),
                dinero: true,
              ),
              pw.SizedBox(width: 24),
              _total(
                'Total por cobrar',
                filas
                    .where((fila) => !fila.anulada)
                    .fold(0.0, (suma, fila) => suma + fila.saldo),
                dinero: true,
              ),
            ],
          ),
        ],
      ),
    );

    if (comentarios.isNotEmpty) {
      documento.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (_) => _encabezado('COMENTARIOS DE ABONOS', rosa),
          footer: _piePagina,
          build: (_) => [
            pw.TableHelper.fromTextArray(
              headers: const [
                'FILA',
                'FACTURA',
                'CLIENTE',
                'ABONO',
                'VALOR',
                'NÚMERO DE RECIBO',
                'COMENTARIO',
              ],
              data: comentarios,
              headerDecoration: pw.BoxDecoration(color: rosa),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.all(6),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
            ),
          ],
        ),
      );
    }

    return documento.save();
  }

  List<List<Object>> _obtenerComentarios(List<FilaVenta> filas) {
    final resultado = <List<Object>>[];
    for (final fila in filas) {
      for (var indice = 0; indice < fila.abonos.length; indice++) {
        final abono = fila.abonos[indice];
        if (abono.valor == 0 &&
            abono.numeroRecibo == null &&
            abono.comentario.trim().isEmpty) {
          continue;
        }
        resultado.add([
          fila.numero,
          fila.numeroFactura,
          fila.cliente,
          'Abono ${indice + 1}',
          _dinero(abono.valor),
          abono.numeroRecibo?.toString() ??
              'Sin número de recibo (registro histórico)',
          abono.comentario,
        ]);
      }
    }
    return resultado;
  }

  pw.Widget _encabezado(String titulo, PdfColor color) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        child: pw.Column(
          children: [
            pw.Text(
              'COSMÉTICOS HG',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(titulo, style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
      );

  pw.Widget _piePagina(pw.Context context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Página ${context.pageNumber} de ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      );

  pw.Widget _total(String etiqueta, double valor, {bool dinero = false}) =>
      pw.Text(
        '$etiqueta: ${dinero ? _dinero(valor) : valor.toInt()}',
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      );

  String _dinero(double valor) => '\$${valor.toStringAsFixed(2)}';

  /// Solo modifica la presentación. Las referencias alfanuméricas se conservan.
  String _referenciaParaPdf(String valor) {
    final limpio = valor.trim();
    if (!RegExp(r'^\d+$').hasMatch(limpio)) return valor;
    return limpio.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  }
}

class _ResumenVendedorPdf {
  _ResumenVendedorPdf(this.nombre);

  final String nombre;
  int facturas = 0;
  int esmaltes = 0;
  double ventas = 0;
  double cobros = 0;
  double saldo = 0;
}
