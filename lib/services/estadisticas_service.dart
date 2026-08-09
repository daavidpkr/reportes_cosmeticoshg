import 'package:supabase_flutter/supabase_flutter.dart';

const nombresMeses = <String>[
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
];

class PeriodoEstadisticas {
  const PeriodoEstadisticas.todo()
      : anio = null,
        mes = null;
  const PeriodoEstadisticas.anio(this.anio) : mes = null;
  const PeriodoEstadisticas.mes(this.anio, this.mes);
  final int? anio;
  final int? mes;
  bool get esTodo => anio == null;
  String get id => esTodo
      ? 'todo'
      : mes == null
          ? '$anio'
          : '$anio-${mes!.toString().padLeft(2, '0')}';
  String get etiqueta => esTodo
      ? 'Todo el histórico'
      : mes == null
          ? '$anio'
          : '${nombresMeses[mes! - 1]} $anio';
}

class RegistroEstadistico {
  const RegistroEstadistico(
      {required this.anio,
      required this.mes,
      required this.referencia,
      required this.cliente,
      required this.fecha,
      required this.vendedor,
      required this.esmaltes,
      required this.venta,
      required this.cobrado});
  final int anio, mes, esmaltes;
  final String referencia, cliente, fecha, vendedor;
  final double venta, cobrado;
  double get porCobrar => venta - cobrado;
  DateTime? get fechaDate => parsearFechaFactura(fecha);
}

class ResumenEstadisticas {
  const ResumenEstadisticas(
      {required this.ventas,
      required this.cobrado,
      required this.porCobrar,
      required this.facturas,
      required this.clientes,
      required this.esmaltes});
  final double ventas, cobrado, porCobrar;
  final int facturas, clientes, esmaltes;
  double get ticketPromedio => facturas == 0 ? 0 : ventas / facturas;
  double get porcentajeCobranza => ventas <= 0 ? 0 : cobrado / ventas * 100;
}

class ResumenVendedor {
  ResumenVendedor(this.nombre);
  final String nombre;
  double ventas = 0, cobrado = 0, porCobrar = 0;
  int facturas = 0;
  double get porcentajeCobranza => ventas <= 0 ? 0 : cobrado / ventas * 100;
}

class ResumenCliente {
  ResumenCliente(this.nombre);
  final String nombre;
  double compras = 0, porCobrar = 0;
  int facturas = 0;
}

class PuntoMensual {
  PuntoMensual(this.anio, this.mes);
  final int anio, mes;
  double ventas = 0, cobros = 0;
  String get etiqueta =>
      '${nombresMeses[mes - 1].substring(0, 3)} ${anio.toString().substring(2)}';
}

class PromedioDia {
  const PromedioDia(this.dia, this.promedio);
  final String dia;
  final double promedio;
}

class IndicadoresClientes {
  const IndicadoresClientes(this.nuevos, this.recurrentes, this.inactivos);
  final int nuevos, recurrentes, inactivos;
}

class EstadisticasData {
  const EstadisticasData(this.periodos, this.registros);
  final List<PeriodoEstadisticas> periodos;
  final List<RegistroEstadistico> registros;

  List<RegistroEstadistico> filtrar(PeriodoEstadisticas periodo) => registros
      .where((r) =>
          periodo.esTodo ||
          (r.anio == periodo.anio &&
              (periodo.mes == null || r.mes == periodo.mes)))
      .toList();

  ResumenEstadisticas resumen(PeriodoEstadisticas p) {
    final filas = filtrar(p);
    return ResumenEstadisticas(
        ventas: filas.fold(0, (s, r) => s + r.venta),
        cobrado: filas.fold(0, (s, r) => s + r.cobrado),
        porCobrar: filas.fold(0, (s, r) => s + r.porCobrar),
        facturas: filas.length,
        clientes: filas
            .map((r) => _clave(r.cliente))
            .where((e) => e.isNotEmpty)
            .toSet()
            .length,
        esmaltes: filas.fold(0, (s, r) => s + r.esmaltes));
  }

  PeriodoEstadisticas? anterior(PeriodoEstadisticas p) {
    if (p.esTodo) return null;
    if (p.mes != null) {
      final d = DateTime(p.anio!, p.mes! - 1);
      return PeriodoEstadisticas.mes(d.year, d.month);
    }
    return PeriodoEstadisticas.anio(p.anio! - 1);
  }

  List<PuntoMensual> evolucion(PeriodoEstadisticas p) {
    final mapa = <String, PuntoMensual>{};
    for (final r in filtrar(p)) {
      final punto = mapa.putIfAbsent(
          '${r.anio}-${r.mes}', () => PuntoMensual(r.anio, r.mes));
      punto.ventas += r.venta;
      punto.cobros += r.cobrado;
    }
    final lista = mapa.values.toList()
      ..sort(
          (a, b) => DateTime(a.anio, a.mes).compareTo(DateTime(b.anio, b.mes)));
    return lista;
  }

  List<ResumenVendedor> vendedores(PeriodoEstadisticas p) {
    final mapa = <String, ResumenVendedor>{};
    for (final r in filtrar(p)) {
      final nombre =
          r.vendedor.trim().isEmpty ? 'Sin vendedor' : r.vendedor.trim();
      final v = mapa.putIfAbsent(nombre, () => ResumenVendedor(nombre));
      v.ventas += r.venta;
      v.cobrado += r.cobrado;
      v.porCobrar += r.porCobrar;
      v.facturas++;
    }
    return mapa.values.toList()..sort((a, b) => b.ventas.compareTo(a.ventas));
  }

  List<ResumenCliente> clientesTop(PeriodoEstadisticas p,
      {bool porDeuda = false}) {
    final mapa = <String, ResumenCliente>{};
    for (final r in filtrar(p)) {
      final nombre =
          r.cliente.trim().isEmpty ? 'Sin cliente' : r.cliente.trim();
      final c = mapa.putIfAbsent(_clave(nombre), () => ResumenCliente(nombre));
      c.compras += r.venta;
      c.porCobrar += r.porCobrar;
      c.facturas++;
    }
    final lista = mapa.values.toList()
      ..sort((a, b) => porDeuda
          ? b.porCobrar.compareTo(a.porCobrar)
          : b.compras.compareTo(a.compras));
    return lista.take(10).toList();
  }

  List<PromedioDia> promedioPorDia(PeriodoEstadisticas p) {
    final totales = List<double>.filled(7, 0),
        fechas = List<Set<String>>.generate(7, (_) => <String>{});
    for (final r in filtrar(p)) {
      final f = r.fechaDate;
      if (f == null) continue;
      final i = f.weekday - 1;
      totales[i] += r.venta;
      fechas[i].add('${f.year}-${f.month}-${f.day}');
    }
    const dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return List.generate(
        7,
        (i) => PromedioDia(
            dias[i], fechas[i].isEmpty ? 0 : totales[i] / fechas[i].length));
  }

  RegistroEstadistico? mayorVenta(PeriodoEstadisticas p) {
    final f = filtrar(p);
    if (f.isEmpty) return null;
    f.sort((a, b) => b.venta.compareTo(a.venta));
    return f.first;
  }

  IndicadoresClientes indicadoresClientes(PeriodoEstadisticas p) {
    final fechados = registros
        .where((r) => r.fechaDate != null && _clave(r.cliente).isNotEmpty)
        .toList();
    if (fechados.isEmpty) return const IndicadoresClientes(0, 0, 0);
    final porCliente = <String, List<DateTime>>{};
    for (final r in fechados) {
      porCliente.putIfAbsent(_clave(r.cliente), () => []).add(r.fechaDate!);
    }
    late DateTime inicio, referencia;
    if (p.esTodo) {
      inicio = fechados
          .map((r) => r.fechaDate!)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      referencia = fechados
          .map((r) => r.fechaDate!)
          .reduce((a, b) => a.isAfter(b) ? a : b);
    } else if (p.mes != null) {
      inicio = DateTime(p.anio!, p.mes!);
      referencia =
          DateTime(p.anio!, p.mes! + 1).subtract(const Duration(days: 1));
    } else {
      inicio = DateTime(p.anio!);
      referencia = DateTime(p.anio! + 1).subtract(const Duration(days: 1));
    }
    final compradores = filtrar(p)
        .map((r) => _clave(r.cliente))
        .where((e) => e.isNotEmpty)
        .toSet();
    var nuevos = 0, recurrentes = 0, inactivos = 0;
    for (final e in porCliente.entries) {
      e.value.sort();
      if (compradores.contains(e.key)) {
        if (!e.value.first.isBefore(inicio)) {
          nuevos++;
        } else {
          recurrentes++;
        }
      }
      final anteriores = e.value.where((f) => !f.isAfter(referencia)).toList();
      if (anteriores.isNotEmpty &&
          referencia.difference(anteriores.last).inDays > 60) {
        inactivos++;
      }
    }
    return IndicadoresClientes(nuevos, recurrentes, inactivos);
  }
}

String _clave(String valor) =>
    valor.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

DateTime? parsearFechaFactura(String valor) {
  final limpio = valor.trim();
  final iso = DateTime.tryParse(limpio);
  if (iso != null) return iso;
  final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})').firstMatch(limpio);
  if (m == null) return null;
  final d = int.parse(m.group(1)!),
      mes = int.parse(m.group(2)!),
      a = int.parse(m.group(3)!);
  final fecha = DateTime(a, mes, d);
  return fecha.year == a && fecha.month == mes && fecha.day == d ? fecha : null;
}

class EstadisticasService {
  EstadisticasService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;
  Future<EstadisticasData> cargar() async {
    final datos = await Future.wait([
      _paginar((d, h) =>
          _client.from('reportes_mensuales').select('anio, mes').range(d, h)),
      _paginar((d, h) => _client
          .from('reportes_ventas')
          .select('mes_reporte, ref_fact, vendedor, esmaltes, abonos')
          .range(d, h)),
      _paginar((d, h) => _client
          .from('facturas_maestras')
          .select('ref_fact, cliente, fecha, venta')
          .range(d, h)),
    ]);
    return construirEstadisticas(
        reportes: datos[0], filas: datos[1], facturas: datos[2]);
  }

  Future<List<Map<String, dynamic>>> _paginar(
      Future<List<Map<String, dynamic>>> Function(int, int) consulta) async {
    const n = 1000;
    final todos = <Map<String, dynamic>>[];
    while (true) {
      final p = await consulta(todos.length, todos.length + n - 1);
      todos.addAll(p);
      if (p.length < n) return todos;
    }
  }
}

EstadisticasData construirEstadisticas(
    {required List<Map<String, dynamic>> reportes,
    required List<Map<String, dynamic>> filas,
    required List<Map<String, dynamic>> facturas}) {
  final periodos = <PeriodoEstadisticas>[];
  final porNombre = <String, PeriodoEstadisticas>{};
  for (final r in reportes) {
    final a = (r['anio'] as num?)?.toInt(), m = (r['mes'] as num?)?.toInt();
    if (a == null || m == null || m < 1 || m > 12) continue;
    final p = PeriodoEstadisticas.mes(a, m);
    periodos.add(p);
    porNombre[p.etiqueta] = p;
  }
  periodos.sort((a, b) => a.id.compareTo(b.id));
  final fm = {
    for (final f in facturas) f['ref_fact']?.toString().trim() ?? '': f
  };
  final registros = <RegistroEstadistico>[];
  for (final fila in filas) {
    final p = porNombre[fila['mes_reporte']?.toString() ?? ''];
    if (p == null) continue;
    final ref = fila['ref_fact']?.toString().trim() ?? '', f = fm[ref];
    final ab = fila['abonos'];
    final double cobrado = ab is List
        ? ab.fold<double>(0, (s, v) => s + ((v as num?)?.toDouble() ?? 0))
        : 0.0;
    registros.add(RegistroEstadistico(
        anio: p.anio!,
        mes: p.mes!,
        referencia: ref,
        cliente: f?['cliente']?.toString() ?? '',
        fecha: f?['fecha']?.toString() ?? '',
        vendedor: fila['vendedor']?.toString() ?? '',
        esmaltes: (fila['esmaltes'] as num?)?.toInt() ?? 0,
        venta: (f?['venta'] as num?)?.toDouble() ?? 0,
        cobrado: cobrado));
  }
  return EstadisticasData(periodos, registros);
}
