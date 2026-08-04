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

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => _encabezado(
          '${vendedor == null ? 'REPORTE GENERAL DE VENTAS' : 'REPORTE DE VENTAS - ${nombresVendedores[vendedor] ?? vendedor}'}${periodo == null ? '' : ' - $periodo'}',
          rosa,
        ),
        footer: _piePagina,
        build: (_) => [
          pw.TableHelper.fromTextArray(
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
                .map((fila) => [
                      fila.numero,
                      fila.referencia,
                      fila.cliente,
                      fila.nombreComercial,
                      fila.fecha,
                      fila.numeroFactura,
                      nombresVendedores[fila.vendedor] ?? fila.vendedor,
                      fila.esmalte,
                      _dinero(fila.venta),
                      fila.abonos
                          .asMap()
                          .entries
                          .where((item) => item.value.valor != 0)
                          .map((item) =>
                              '${item.key + 1}: ${_dinero(item.value.valor)}')
                          .join(' / '),
                      _dinero(fila.totalAbonos),
                      _dinero(fila.saldo),
                    ])
                .toList(),
            headerDecoration: pw.BoxDecoration(color: rosa),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 5,
            ),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              _total(
                  'Total esmaltes',
                  filas
                      .fold(0, (suma, fila) => suma + fila.esmalte)
                      .toDouble()),
              pw.SizedBox(width: 24),
              _total('Total ventas',
                  filas.fold(0.0, (suma, fila) => suma + fila.venta),
                  dinero: true),
              pw.SizedBox(width: 24),
              _total('Total cobros',
                  filas.fold(0.0, (suma, fila) => suma + fila.totalAbonos),
                  dinero: true),
              pw.SizedBox(width: 24),
              _total('Total por cobrar',
                  filas.fold(0.0, (suma, fila) => suma + fila.saldo),
                  dinero: true),
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
              oddRowDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey100),
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
        if (abono.comentario.trim().isEmpty) continue;
        resultado.add([
          fila.numero,
          fila.numeroFactura,
          fila.cliente,
          'Abono ${indice + 1}',
          _dinero(abono.valor),
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
}
