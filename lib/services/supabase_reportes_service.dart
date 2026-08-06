import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/factura.dart';
import '../models/fila_venta.dart';

class SupabaseReportesService {
  SupabaseReportesService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> obtenerReportesMensuales() async {
    final respuesta = await _client
        .from('reportes_mensuales')
        .select('id, anio, mes')
        .order('anio', ascending: true)
        .order('mes', ascending: true);

    return List<Map<String, dynamic>>.from(respuesta);
  }

  Future<void> guardarReporteMensual(int anio, int mes) async {
    final id = '$anio-${mes.toString().padLeft(2, '0')}';

    await _client.from('reportes_mensuales').upsert(
      {
        'id': id,
        'anio': anio,
        'mes': mes,
      },
      onConflict: 'id',
    );
  }

  Future<void> eliminarReporteMensual(int anio, int mes) async {
    final id = '$anio-${mes.toString().padLeft(2, '0')}';

    await _client.from('reportes_mensuales').delete().eq('id', id);
  }

  Future<void> eliminarFilasReporte(String mesReporte) async {
    await _client
        .from('reportes_ventas')
        .delete()
        .eq('mes_reporte', mesReporte);
  }

  Future<Factura?> buscarFacturaPorRef(String referencia) async {
    final ref = referencia.trim();
    if (ref.isEmpty) return null;

    final respuesta = await _client
        .from('facturas_maestras')
        .select()
        .eq('ref_fact', ref)
        .maybeSingle();
    if (respuesta == null) return null;

    return Factura(
      cliente: respuesta['cliente']?.toString() ?? '',
      nombreComercial: respuesta['nombre_comercial']?.toString() ?? '',
      fecha: respuesta['fecha']?.toString() ?? '',
      secuencial: respuesta['ref_fact']?.toString() ?? ref,
      total: (respuesta['venta'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<void> guardarFactura(Factura factura) =>
      _client.from('facturas_maestras').upsert({
        'ref_fact': factura.secuencial,
        'cliente': factura.cliente,
        'nombre_comercial': factura.nombreComercial,
        'fecha': factura.fecha,
        'nro_fact': factura.secuencial,
        'venta': factura.total,
      }, onConflict: 'ref_fact');

  Future<void> guardarFacturas(Iterable<Factura> facturas) async {
    final datos = facturas
        .map((factura) => {
              'ref_fact': factura.secuencial,
              'cliente': factura.cliente,
              'nombre_comercial': factura.nombreComercial,
              'fecha': factura.fecha,
              'nro_fact': factura.secuencial,
              'venta': factura.total,
            })
        .toList();
    if (datos.isEmpty) return;
    await _client.from('facturas_maestras').upsert(
          datos,
          onConflict: 'ref_fact',
        );
  }

  Future<void> guardarFila(FilaVenta fila, String mesReporte) async {
    final referencia = fila.numeroFactura.trim();

    // La factura maestra siempre se persiste antes que el reporte que la usa.
    if (referencia.isNotEmpty) {
      await _client.from('facturas_maestras').upsert({
        'ref_fact': referencia,
        'cliente': fila.cliente,
        'nombre_comercial': fila.nombreComercial,
        'fecha': fila.fecha,
        'nro_fact': referencia,
        'venta': fila.venta,
      }, onConflict: 'ref_fact');
    }

    await _client.from('reportes_ventas').upsert(
      {
        'nro_fila': fila.numero,
        'ref_fact': referencia,
        'vendedor': fila.vendedor,
        'esmaltes': fila.esmalte,
        'abonos': fila.abonos.map((abono) => abono.valor).toList(),
        'comentarios_abonos':
            fila.abonos.map((abono) => abono.comentario).toList(),
        'mes_reporte': mesReporte,
      },
      onConflict: 'nro_fila,mes_reporte',
    );
  }

  Future<void> eliminarFila(int numeroFila, String mesReporte) => _client
      .from('reportes_ventas')
      .delete()
      .eq('nro_fila', numeroFila)
      .eq('mes_reporte', mesReporte);

  Future<void> eliminarFacturaMaestra(String referencia) async {
    final ref = referencia.trim();
    if (ref.isEmpty) {
      throw Exception('La referencia de la factura está vacía.');
    }

    await _client.from('facturas_maestras').delete().eq('ref_fact', ref);
  }

  Stream<List<Map<String, dynamic>>> observarFilas(String mesReporte) => _client
      .from('reportes_ventas')
      .stream(primaryKey: ['id'])
      .eq('mes_reporte', mesReporte)
      .order('nro_fila', ascending: true);
}
