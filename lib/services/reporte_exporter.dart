import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/fila_venta.dart';
import 'web_download_stub.dart'
    if (dart.library.js_interop) 'web_download.dart';

class ReporteExporter {
  static const _nombreArchivo = 'reporte_ventas_cosmeticos_hg.pdf';

  Future<String> guardar(List<FilaVenta> filas) async {
    final bytes = await _generarPdf(filas);

    if (kIsWeb) {
      descargarArchivoWeb(bytes, _nombreArchivo);
      return _nombreArchivo;
    }

    final directorio = await getApplicationDocumentsDirectory();
    final archivo = File(
      '${directorio.path}${Platform.pathSeparator}$_nombreArchivo',
    );
    await archivo.writeAsBytes(bytes, flush: true);
    return archivo.path;
  }

  Future<Uint8List> _generarPdf(List<FilaVenta> filas) async {
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
        header: (_) => _encabezado('REPORTE DE VENTAS', rosa),
        footer: _piePagina,
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: const [
              'NRO',
              'REF.',
              'CLIENTE',
              'FECHA',
              'NRO. FACT.',
              'ESMALTE',
              'VENTA',
              'ABONO 1',
              'ABONO 2',
              'TOT. ABONO',
              'SALDO',
            ],
            data: filasConDatos
                .map((fila) => [
                      fila.numero,
                      fila.referencia,
                      fila.cliente,
                      fila.fecha,
                      fila.numeroFactura,
                      fila.esmalte.toStringAsFixed(2),
                      _dinero(fila.venta),
                      _dinero(fila.abono1),
                      _dinero(fila.abono2),
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
              _total('Total esmaltes',
                  filas.fold(0.0, (suma, fila) => suma + fila.esmalte)),
              pw.SizedBox(width: 24),
              _total('Total ventas',
                  filas.fold(0.0, (suma, fila) => suma + fila.venta),
                  dinero: true),
              pw.SizedBox(width: 24),
              _total('Total cobros',
                  filas.fold(0.0, (suma, fila) => suma + fila.totalAbonos),
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
      if (fila.comentario1.trim().isNotEmpty) {
        resultado.add([
          fila.numero,
          fila.numeroFactura,
          fila.cliente,
          'Abono 1',
          _dinero(fila.abono1),
          fila.comentario1,
        ]);
      }
      if (fila.comentario2.trim().isNotEmpty) {
        resultado.add([
          fila.numero,
          fila.numeroFactura,
          fila.cliente,
          'Abono 2',
          _dinero(fila.abono2),
          fila.comentario2,
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
        '$etiqueta: ${dinero ? _dinero(valor) : valor.toStringAsFixed(2)}',
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      );

  String _dinero(double valor) => '\$${valor.toStringAsFixed(2)}';
}
