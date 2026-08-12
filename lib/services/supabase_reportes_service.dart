import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/factura.dart';
import '../models/fila_venta.dart';
import '../models/billing_customer.dart';
import 'request_id.dart';

Map<String, dynamic> construirParametrosGuardarFila({
  required FilaVenta fila,
  required String mesReporte,
  required String requestId,
  DateTime? invoiceDate,
}) {
  // The model always has two empty payment controls for the UI. They are not
  // payments and must reach PostgreSQL as three genuinely empty arrays.
  final payments = fila.abonos.where(
    (item) =>
        item.valor != 0 ||
        item.numeroRecibo != null ||
        item.comentario.trim().isNotEmpty,
  );

  return {
    'p_request_id': requestId,
    'p_row_number': fila.numero,
    'p_report_name': mesReporte,
    'p_ref_fact': fila.referencia.trim(),
    'p_invoice_number': fila.numeroFactura.trim(),
    'p_cliente': fila.cliente,
    'p_commercial_name': fila.nombreComercial,
    'p_invoice_date': invoiceDate?.toIso8601String().substring(0, 10),
    'p_sale': fila.venta,
    'p_seller': fila.vendedor,
    'p_nail_polish': fila.esmalte,
    'p_payments': payments.map((item) => item.valor).toList(),
    'p_payment_receipts': payments.map((item) => item.numeroRecibo).toList(),
    'p_payment_comments': payments.map((item) => item.comentario).toList(),
  };
}

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
        'Diciembre'
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
    saldosPorReporte.update(
      nombreReporte,
      (total) => total + fila.saldo,
      ifAbsent: () => fila.saldo,
    );
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

/// Une las filas operativas con su factura maestra sin depender del mes activo.
/// La clave compuesta evita duplicar una fila al reconstruir el consolidado.
List<FilaVenta> construirFilasConsolidadas({
  required List<Map<String, dynamic>> filas,
  required List<Map<String, dynamic>> facturas,
}) {
  final facturasPorRef = <String, Map<String, dynamic>>{
    for (final factura in facturas)
      factura['ref_fact']?.toString().trim() ?? '': factura,
  };
  final unicas = <String, FilaVenta>{};
  for (final dato in filas) {
    final referencia = dato['ref_fact']?.toString().trim() ?? '';
    if (referencia.isEmpty) continue;
    final factura = facturasPorRef[referencia];
    if (factura == null) continue;
    final abonos = dato['abonos'] is List ? dato['abonos'] as List : const [];
    final recibos = dato['numeros_recibo'] is List
        ? dato['numeros_recibo'] as List
        : const [];
    final comentarios = dato['comentarios_abonos'] is List
        ? dato['comentarios_abonos'] as List
        : const [];
    final pagos = List<Abono>.generate(abonos.length, (indice) {
      return Abono(
        valor: (abonos[indice] as num?)?.toDouble() ?? 0,
        numeroRecibo: indice < recibos.length && recibos[indice] != null
            ? int.tryParse(recibos[indice].toString())
            : null,
        comentario: indice < comentarios.length
            ? comentarios[indice]?.toString() ?? ''
            : '',
      );
    });
    while (pagos.length < 2) {
      pagos.add(Abono());
    }
    final numero = (dato['nro_fila'] as num?)?.toInt() ?? 0;
    final mes = dato['mes_reporte']?.toString() ?? '';
    unicas['$mes::$numero'] = FilaVenta(
      numero: numero,
      referencia: referencia,
      cliente: factura['cliente']?.toString() ?? '',
      nombreComercial: factura['nombre_comercial']?.toString() ?? '',
      fecha: factura['fecha']?.toString() ?? '',
      numeroFactura: factura['nro_fact']?.toString() ?? '',
      vendedor: dato['vendedor']?.toString() ?? '',
      esmalte: (dato['esmaltes'] as num?)?.toInt() ?? 0,
      venta: (factura['venta'] as num?)?.toDouble() ?? 0,
      abonos: pagos,
    );
  }
  final resultado = unicas.values.toList();
  resultado.sort((a, b) {
    final fecha = b.fecha.compareTo(a.fecha);
    return fecha != 0 ? fecha : b.numeroFactura.compareTo(a.numeroFactura);
  });
  return resultado;
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
      _obtenerEnPaginas(
        (desde, hasta) => _client
            .from('reportes_ventas')
            .select('mes_reporte, ref_fact, abonos')
            .range(desde, hasta),
      );

  Future<List<FilaVenta>> obtenerFilasConsolidadas() async {
    final resultados = await Future.wait([
      _obtenerEnPaginas(
        (desde, hasta) => _client
            .from('reportes_ventas')
            .select(
              'mes_reporte,nro_fila,ref_fact,vendedor,esmaltes,abonos,'
              'numeros_recibo,comentarios_abonos',
            )
            .order('mes_reporte', ascending: false)
            .order('nro_fila', ascending: false)
            .range(desde, hasta),
      ),
      _obtenerEnPaginas(
        (desde, hasta) => _client
            .from('facturas_maestras')
            .select(
              'ref_fact,cliente,nombre_comercial,fecha,nro_fact,venta',
            )
            .range(desde, hasta),
      ),
    ]);
    return construirFilasConsolidadas(
      filas: resultados[0],
      facturas: resultados[1],
    );
  }

  Future<List<Map<String, dynamic>>> _obtenerTodasLasFacturas() =>
      _obtenerEnPaginas(
        (desde, hasta) => _client
            .from('facturas_maestras')
            .select('ref_fact, venta')
            .range(desde, hasta),
      );

  Future<List<Map<String, dynamic>>> _obtenerEnPaginas(
    Future<List<Map<String, dynamic>>> Function(int, int) consulta,
  ) =>
      obtenerTodasLasPaginas(consulta);

  static Future<List<Map<String, dynamic>>> obtenerTodasLasPaginas(
    Future<List<Map<String, dynamic>>> Function(int, int) consulta, {
    int tamano = 1000,
  }) async {
    final todos = <Map<String, dynamic>>[];
    while (true) {
      final pagina = await consulta(todos.length, todos.length + tamano - 1);
      todos.addAll(pagina);
      if (pagina.length < tamano) return todos;
    }
  }

  Future<void> guardarReporteMensual(int anio, int mes) async {
    await _client.rpc('enterprise_save_monthly_report', params: {
      'p_request_id': newRequestId(),
      'p_year': anio,
      'p_month': mes,
    });
  }

  Future<void> eliminarReporteMensual(int anio, int mes) async {
    await _client.rpc('enterprise_delete_monthly_report', params: {
      'p_request_id': newRequestId(),
      'p_year': anio,
      'p_month': mes,
    });
  }

  Future<void> eliminarFilasReporte(String mesReporte) async {
    await _client.rpc('enterprise_delete_report_rows', params: {
      'p_request_id': newRequestId(),
      'p_report_name': mesReporte,
    });
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
      secuencial: respuesta['nro_fact']?.toString() ?? ref,
      total: (respuesta['venta'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<void> guardarFactura(Factura factura) => _guardarFacturaRpc(factura);

  Future<void> guardarFacturas(Iterable<Factura> facturas) async {
    for (final factura in facturas) {
      await _guardarFacturaRpc(factura);
    }
  }

  Future<void> guardarFila(FilaVenta fila, String mesReporte) async {
    final referencia = fila.referencia.trim();

    final date = parseInvoiceDate(fila.fecha);
    if (referencia.isNotEmpty && date == null) {
      throw const FormatException('Fecha de factura inválida.');
    }
    await _client.rpc(
      'enterprise_save_report_row',
      params: construirParametrosGuardarFila(
        fila: fila,
        mesReporte: mesReporte,
        requestId: newRequestId(),
        invoiceDate: date,
      ),
    );
  }

  Future<void> eliminarFila(int numeroFila, String mesReporte) =>
      _client.rpc('enterprise_delete_report_row', params: {
        'p_request_id': newRequestId(),
        'p_row_number': numeroFila,
        'p_report_name': mesReporte,
      });

  Future<void> eliminarFacturaMaestra(String referencia) async {
    final ref = referencia.trim();
    if (ref.isEmpty) {
      throw Exception('La referencia de la factura está vacía.');
    }

    await _client.rpc('enterprise_delete_invoice', params: {
      'p_request_id': newRequestId(),
      'p_factura_id': ref,
    });
  }

  Future<void> _guardarFacturaRpc(Factura factura) async {
    final date = parseInvoiceDate(factura.fecha);
    if (date == null) throw const FormatException('Fecha de factura inválida.');
    await _client.rpc('enterprise_upsert_invoice', params: {
      'p_request_id': newRequestId(),
      'p_ref_fact': factura.secuencial,
      'p_cliente': factura.cliente,
      'p_nombre_comercial': factura.nombreComercial,
      'p_fecha': date.toIso8601String().substring(0, 10),
      'p_nro_fact': factura.secuencial,
      'p_venta': factura.total,
    });
  }

  Stream<List<Map<String, dynamic>>> observarFilas(String mesReporte) => _client
      .from('reportes_ventas')
      .stream(primaryKey: ['id'])
      .eq('mes_reporte', mesReporte)
      .order('nro_fila', ascending: true);
}
