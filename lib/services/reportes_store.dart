import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/factura.dart';
import '../models/fila_venta.dart';

class ReporteMensual {
  ReporteMensual(
      {required this.anio,
      required this.mes,
      List<FilaVenta>? filas,
      List<Factura>? facturas})
      : filas = filas ?? List.generate(15, (i) => FilaVenta(numero: i + 1)),
        facturas = facturas ?? [];

  final int anio;
  final int mes;
  List<FilaVenta> filas;
  List<Factura> facturas;
  String get id => '$anio-${mes.toString().padLeft(2, '0')}';
  String get nombre => '${const [
        'Enero',
        'Febrero',
        'Marzo',
        'Abril',
        'Mayo',
        'Junio',
        'Julio',
        'Agosto',
        'Septiembre',
        'Octubre',
        'Noviembre',
        'Diciembre'
      ][mes - 1]} $anio';

  Map<String, dynamic> toJson() => {
        'anio': anio,
        'mes': mes,
        'filas': filas.map((e) => e.toJson()).toList(),
        'facturas': facturas.map((e) => e.toJson()).toList()
      };
  factory ReporteMensual.fromJson(Map<String, dynamic> json) => ReporteMensual(
        anio: json['anio'] as int,
        mes: json['mes'] as int,
        filas: (json['filas'] as List)
            .map((e) => FilaVenta.fromJson(e as Map<String, dynamic>))
            .toList(),
        facturas: (json['facturas'] as List? ?? const [])
            .map((e) => Factura.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ReportesStore {
  static const _clave = 'reportes_mensuales_v1';
  static const _claveActivo = 'reporte_mensual_activo';
  final List<ReporteMensual> reportes = [];
  late ReporteMensual activo;

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final texto = prefs.getString(_clave);
    reportes.clear();
    if (texto != null) {
      reportes.addAll((jsonDecode(texto) as List)
          .map((e) => ReporteMensual.fromJson(e as Map<String, dynamic>)));
    }
    if (reportes.isEmpty) reportes.add(ReporteMensual(anio: 2026, mes: 7));
    reportes.sort((a, b) => a.id.compareTo(b.id));
    final id = prefs.getString(_claveActivo);
    activo = reportes.where((e) => e.id == id).firstOrNull ?? reportes.last;
  }

  bool crear(int anio, int mes) {
    if (reportes.any((e) => e.anio == anio && e.mes == mes)) return false;
    activo = ReporteMensual(anio: anio, mes: mes);
    reportes.add(activo);
    reportes.sort((a, b) => a.id.compareTo(b.id));
    return true;
  }

  ReporteMensual eliminarActivo() {
    final eliminado = activo;
    reportes.remove(eliminado);
    if (reportes.isEmpty) {
      final siguiente = DateTime(eliminado.anio, eliminado.mes + 1);
      reportes.add(
        ReporteMensual(anio: siguiente.year, mes: siguiente.month),
      );
    }
    activo = reportes.last;
    return eliminado;
  }

  Future<void> guardar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _clave, jsonEncode(reportes.map((e) => e.toJson()).toList()));
    await prefs.setString(_claveActivo, activo.id);
  }
}
