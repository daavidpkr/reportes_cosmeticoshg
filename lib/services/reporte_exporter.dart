import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/fila_venta.dart';

class ReporteExporter {
  Future<String?> guardar(List<FilaVenta> filas) async {
    final contenido = _generarCsv(filas);
    final bytes = Uint8List.fromList(utf8.encode('\ufeff$contenido'));

    if (kIsWeb) {
      return FilePicker.platform.saveFile(
        dialogTitle: 'Guardar reporte de ventas',
        fileName: 'reporte_ventas_cosmeticos_hg.csv',
        bytes: bytes,
      );
    }

    final directorio = await getApplicationDocumentsDirectory();
    final archivo = File(
        '${directorio.path}${Platform.pathSeparator}reporte_ventas_cosmeticos_hg.csv');
    await archivo.writeAsBytes(bytes, flush: true);
    return archivo.path;
  }

  String _generarCsv(List<FilaVenta> filas) {
    final buffer = StringBuffer()
      ..writeln(
          'NRO,REF,CLIENTE,FECHA,NRO_FACT,ESMALTE,VENTA,ABO_1,COM_1,ABO_2,COM_2,TOT_ABO,TOTAL');
    for (final fila in filas.where((fila) => fila.tieneDatos)) {
      buffer.writeln([
        fila.numero,
        _campo(fila.referencia),
        _campo(fila.cliente),
        _campo(fila.fecha),
        _campo(fila.numeroFactura),
        fila.esmalte,
        fila.venta,
        fila.abono1,
        _campo(fila.comentario1),
        fila.abono2,
        _campo(fila.comentario2),
        fila.totalAbonos,
        fila.saldo,
      ].join(','));
    }
    return buffer.toString();
  }

  String _campo(String valor) => '"${valor.replaceAll('"', '""')}"';
}
