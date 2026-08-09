import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/factura.dart';
import '../models/fila_venta.dart';

class CobroMensual {
  const CobroMensual({
    required this.anio,
    required this.mes,
    required this.valorPorCobrar,
  });

  final int anio;
  final int mes;
  final double valorPorCobrar;

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
        'Diciembre',
      ][mes - 1]} $anio';
}

List<CobroMensual> calcularCobrosMensuales({
  required List<Map<String, dynamic>> reportes,
  required List<Map<String, dynamic>> filas,
  required List<Map<String, dynamic>> facturas,
}) {
  final ventasPorReferencia = <String, double>{
    for (final factura in facturas)
      factura['ref_fact']?.toString().trim() ?? '':
          (factura['venta'] as num?)?.toDouble() ?? 0,
  };
  final saldosPorReporte = <String, double>{};
  for (final dato in filas) {
    final nombreReporte = dato['mes_reporte']?.toString() ?? '';
    final referencia = dato['ref_fact']?.toString().trim() ?? '';
    final abonos = dato['abonos'];
    final fila = FilaVenta(
      numero: 0,
      venta: ventasPorReferencia[referencia] ?? 0,
      abonos: abonos is List
          ? abonos
              .map((valor) => Abono(valor: (valor as num?)?.toDouble() ?? 0))
              .toList()
          : <Abono>[],
    );
    saldosPorReporte.update(nombreReporte, (total) => total + fila.saldo,
        ifAbsent: () => fila.saldo);
  }
  return reportes.map((reporte) {
    final anio = (reporte['anio'] as num).toInt();
    final mes = (reporte['mes'] as num).toInt();
    final cobro = CobroMensual(anio: anio, mes: mes, valorPorCobrar: 0);
    return CobroMensual(
      anio: anio,
      mes: mes,
      valorPorCobrar: saldosPorReporte[cobro.nombre] ?? 0,
    );
  }).toList();
}

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

  /// Calcula el mismo saldo que [FilaVenta.saldo] para cada reporte existente.
  /// Supabase es la única fuente: no utiliza el estado ni el almacenamiento local.
  Future<List<CobroMensual>> obtenerCobrosMensuales() async {
    final resultados = await Future.wait([
      obtenerReportesMensuales(),
      _obtenerTodasLasFilas(),
      _obtenerTodasLasFacturas(),
    ]);
    return calcularCobrosMensuales(
      reportes: List<Map<String, dynamic>>.from(resultados[0] as List),
      filas: List<Map<String, dynamic>>.from(resultados[1] as List),
      facturas: List<Map<String, dynamic>>.from(resultados[2] as List),
    );
  }

  Future<List<Map<String, dynamic>>> _obtenerTodasLasFilas() =>
      _obtenerEnPaginas((desde, hasta) => _client
          .from('reportes_ventas')
          .select('mes_reporte, ref_fact, abonos')
          .range(desde, hasta));

  Future<List<Map<String, dynamic>>> _obtenerTodasLasFacturas() =>
      _obtenerEnPaginas((desde, hasta) => _client
          .from('facturas_maestras')
          .select('ref_fact, venta')
          .range(desde, hasta));

  Future<List<Map<String, dynamic>>> _obtenerEnPaginas(
    Future<List<Map<String, dynamic>>> Function(int, int) consulta,
  ) async {
    const tamano = 1000;
    final todos = <Map<String, dynamic>>[];
    while (true) {
      final pagina = await consulta(todos.length, todos.length + tamano - 1);
      todos.addAll(pagina);
      if (pagina.length < tamano) return todos;
    }
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
