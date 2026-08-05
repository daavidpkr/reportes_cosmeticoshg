import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/factura.dart';
import '../models/fila_venta.dart';

class SupabaseReportesService {
  SupabaseReportesService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

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

  Future<void> guardarFila(FilaVenta fila, String mesReporte) =>
      _client.from('reportes_ventas').upsert({
        'nro_fila': fila.numero,
        'ref_fact': fila.referencia,
        'vendedor': fila.vendedor,
        'esmaltes': fila.esmalte,
        'abonos': fila.abonos.map((abono) => abono.valor).toList(),
        'mes_reporte': mesReporte,
      }, onConflict: 'nro_fila,mes_reporte');

  Stream<List<Map<String, dynamic>>> observarFilas(String mesReporte) => _client
      .from('reportes_ventas')
      .stream(primaryKey: ['id'])
      .eq('mes_reporte', mesReporte)
      .order('nro_fila', ascending: true);
}
