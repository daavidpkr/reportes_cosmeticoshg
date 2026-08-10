import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/estadisticas_service.dart';
import '../theme/hg_theme.dart';

class EstadisticasScreen extends StatefulWidget {
  const EstadisticasScreen({super.key});
  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {
  final _service = EstadisticasService();
  EstadisticasData? _data;
  Object? _error;
  bool _cargando = true, _porDeuda = false;
  String _periodo = 'todo';
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final d = await _service.cargar();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  PeriodoEstadisticas get _seleccion {
    if (_periodo == 'todo') return const PeriodoEstadisticas.todo();
    final partes = _periodo.split('-');
    return partes.length == 1
        ? PeriodoEstadisticas.anio(int.parse(partes[0]))
        : PeriodoEstadisticas.mes(int.parse(partes[0]), int.parse(partes[1]));
  }

  String _dinero(double v) =>
      '\$${v.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+\.)'), (m) => '${m[1]},')}';
  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Cargando estadísticas…'),
          ],
        ),
      );
    }
    if (_error != null) {
      return _Estado(
        icon: Icons.cloud_off_outlined,
        texto: 'No se pudieron cargar las estadísticas.',
        accion: _cargar,
      );
    }
    final d = _data!;
    if (d.periodos.isEmpty) {
      return _Estado(
        icon: Icons.insights_outlined,
        texto: 'Todavía no existen períodos para analizar.',
        accion: _cargar,
      );
    }
    final p = _seleccion,
        r = d.resumen(p),
        filas = d.filtrar(p),
        anterior = d.anterior(p),
        ra = anterior == null ? null : d.resumen(anterior);
    final variacion = ra == null || ra.ventas == 0
        ? null
        : (r.ventas - ra.ventas) / ra.ventas * 100;
    final opciones = <PeriodoEstadisticas>[
      const PeriodoEstadisticas.todo(),
      ...d.periodos.map((e) => PeriodoEstadisticas.anio(e.anio)).toSet(),
      ...d.periodos,
    ];
    return RefreshIndicator(
      onRefresh: _cargar,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(c.maxWidth < 600 ? 14 : 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1500),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 20,
                    runSpacing: 12,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estadísticas',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: context.hg.plum,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Análisis comercial y de cobranza',
                            style: TextStyle(color: context.hg.mutedText),
                          ),
                        ],
                      ),
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String>(
                          initialValue: _periodo,
                          decoration: const InputDecoration(
                            labelText: 'Período',
                            prefixIcon: Icon(Icons.calendar_month_outlined),
                            isDense: true,
                          ),
                          items: opciones
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.id,
                                  child: Text(e.etiqueta),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _periodo = v ?? 'todo'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (filas.isEmpty)
                    const _Estado(
                      icon: Icons.event_busy_outlined,
                      texto: 'Este período no tiene movimientos.',
                    )
                  else ...[
                    LayoutBuilder(
                      builder: (context, k) => GridView.count(
                        crossAxisCount: k.maxWidth >= 1100
                            ? 4
                            : k.maxWidth >= 650
                            ? 2
                            : 1,
                        childAspectRatio: k.maxWidth >= 650 ? 2.35 : 3.2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _Kpi(
                            'VENTAS TOTALES',
                            _dinero(r.ventas),
                            Icons.trending_up,
                            detalle: variacion == null
                                ? (p.esTodo
                                      ? null
                                      : 'Sin período anterior comparable')
                                : '${variacion >= 0 ? '↑' : '↓'} ${variacion.abs().toStringAsFixed(1)}% vs. ${anterior!.etiqueta}',
                            positivo: variacion != null && variacion >= 0,
                          ),
                          _Kpi(
                            'TOTAL COBRADO',
                            _dinero(r.cobrado),
                            Icons.payments_outlined,
                          ),
                          _Kpi(
                            'POR COBRAR',
                            _dinero(r.porCobrar),
                            Icons.account_balance_wallet_outlined,
                          ),
                          _Kpi(
                            'FACTURAS',
                            '${r.facturas}',
                            Icons.receipt_long_outlined,
                          ),
                          _Kpi(
                            'CLIENTES',
                            '${r.clientes}',
                            Icons.people_outline,
                          ),
                          _Kpi(
                            'ESMALTES VENDIDOS',
                            '${r.esmaltes}',
                            Icons.auto_awesome_outlined,
                          ),
                          _Kpi(
                            'TICKET PROMEDIO',
                            _dinero(r.ticketPromedio),
                            Icons.calculate_outlined,
                          ),
                          _Mayor(registro: d.mayorVenta(p), dinero: _dinero),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Seccion(
                      titulo: 'Evolución de ventas y cobros',
                      child: SizedBox(
                        height: 280,
                        child: _LineChart(
                          puntos: d.evolucion(p),
                          dinero: _dinero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, k) {
                        final widgets = [
                          _Seccion(
                            titulo: 'Estado de cobranza',
                            child: _Cobranza(r: r, dinero: _dinero),
                          ),
                          _Seccion(
                            titulo: 'Indicadores de clientes',
                            child: _IndicadoresClientes(
                              datos: d.indicadoresClientes(p),
                            ),
                          ),
                          _Seccion(
                            titulo: 'Venta promedio por día de la semana',
                            child: SizedBox(
                              height: 230,
                              child: _BarChart(
                                datos: d.promedioPorDia(p),
                                dinero: _dinero,
                              ),
                            ),
                          ),
                        ];
                        return k.maxWidth > 1100
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0; i < widgets.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 16),
                                    Expanded(child: widgets[i]),
                                  ],
                                ],
                              )
                            : Column(
                                children: [
                                  for (var i = 0; i < widgets.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 16),
                                    widgets[i],
                                  ],
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 16),
                    _Seccion(
                      titulo: 'Ranking de vendedores',
                      child: _TablaVendedores(
                        datos: d.vendedores(p),
                        dinero: _dinero,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Seccion(
                      titulo: 'Top clientes',
                      trailing: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Mayores compras'),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Mayor deuda'),
                          ),
                        ],
                        selected: {_porDeuda},
                        onSelectionChanged: (v) =>
                            setState(() => _porDeuda = v.first),
                      ),
                      child: _TablaClientes(
                        datos: d.clientesTop(p, porDeuda: _porDeuda),
                        dinero: _dinero,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(
    this.titulo,
    this.valor,
    this.icono, {
    this.detalle,
    this.positivo = false,
  });
  final String titulo, valor;
  final IconData icono;
  final String? detalle;
  final bool positivo;
  @override
  Widget build(BuildContext c) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.hg.hover,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icono, color: c.hg.burgundy),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: c.hg.mutedText,
                    letterSpacing: .4,
                  ),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    valor,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (detalle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    detalle!,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: positivo ? c.hg.positive : c.hg.mutedText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Mayor extends StatelessWidget {
  const _Mayor({required this.registro, required this.dinero});
  final RegistroEstadistico? registro;
  final String Function(double) dinero;
  @override
  Widget build(BuildContext c) {
    final r = registro;
    return _Kpi(
      'MAYOR VENTA',
      r == null ? '—' : dinero(r.venta),
      Icons.emoji_events_outlined,
      detalle: r == null
          ? null
          : '${r.cliente.isEmpty ? 'Sin cliente' : r.cliente} · ${r.fecha}',
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.child, this.trailing});
  final String titulo;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext c) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                titulo,
                style: Theme.of(c).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.hg.plum,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    ),
  );
}

class _Cobranza extends StatelessWidget {
  const _Cobranza({required this.r, required this.dinero});
  final ResumenEstadisticas r;
  final String Function(double) dinero;
  @override
  Widget build(BuildContext c) {
    final pct = r.porcentajeCobranza.clamp(0, 100);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _Dato('Ventas', dinero(r.ventas))),
            Expanded(child: _Dato('Cobrado', dinero(r.cobrado))),
            Expanded(child: _Dato('Por cobrar', dinero(r.porCobrar))),
          ],
        ),
        const SizedBox(height: 25),
        LinearProgressIndicator(
          value: pct / 100,
          minHeight: 14,
          borderRadius: BorderRadius.circular(8),
          color: c.hg.positive,
          backgroundColor: c.hg.positiveContainer,
        ),
        const SizedBox(height: 10),
        Text(
          '${r.porcentajeCobranza.toStringAsFixed(1)}% de cobranza',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.t, this.v);
  final String t, v;
  @override
  Widget build(BuildContext c) => Column(
    children: [
      Text(t, style: TextStyle(fontSize: 11, color: c.hg.mutedText)),
      const SizedBox(height: 4),
      FittedBox(
        child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    ],
  );
}

class _IndicadoresClientes extends StatelessWidget {
  const _IndicadoresClientes({required this.datos});
  final IndicadoresClientes datos;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: _Dato('Nuevos', '${datos.nuevos}')),
      Expanded(child: _Dato('Recurrentes', '${datos.recurrentes}')),
      Expanded(child: _Dato('Inactivos (60 días)', '${datos.inactivos}')),
    ],
  );
}

class _TablaVendedores extends StatelessWidget {
  const _TablaVendedores({required this.datos, required this.dinero});
  final List<ResumenVendedor> datos;
  final String Function(double) dinero;
  @override
  Widget build(BuildContext c) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columns: const [
        DataColumn(label: Text('#')),
        DataColumn(label: Text('Vendedor')),
        DataColumn(label: Text('Ventas')),
        DataColumn(label: Text('Facturas')),
        DataColumn(label: Text('Cobrado')),
        DataColumn(label: Text('Por cobrar')),
        DataColumn(label: Text('% cobranza')),
      ],
      rows: List.generate(datos.length, (i) {
        final v = datos[i];
        return DataRow(
          cells: [
            DataCell(
              Text(
                '${i + 1}',
                style: TextStyle(
                  color: i < 3 ? c.hg.gold : null,
                  fontWeight: i < 3 ? FontWeight.w800 : null,
                ),
              ),
            ),
            DataCell(Text(v.nombre)),
            DataCell(Text(dinero(v.ventas))),
            DataCell(Text('${v.facturas}')),
            DataCell(Text(dinero(v.cobrado))),
            DataCell(Text(dinero(v.porCobrar))),
            DataCell(Text('${v.porcentajeCobranza.toStringAsFixed(1)}%')),
          ],
        );
      }),
    ),
  );
}

class _TablaClientes extends StatelessWidget {
  const _TablaClientes({required this.datos, required this.dinero});
  final List<ResumenCliente> datos;
  final String Function(double) dinero;
  @override
  Widget build(BuildContext c) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columns: const [
        DataColumn(label: Text('Cliente')),
        DataColumn(label: Text('Facturas')),
        DataColumn(label: Text('Compras')),
        DataColumn(label: Text('Por cobrar')),
      ],
      rows: datos
          .map(
            (v) => DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 240,
                    child: Text(v.nombre, overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataCell(Text('${v.facturas}')),
                DataCell(Text(dinero(v.compras))),
                DataCell(Text(dinero(v.porCobrar))),
              ],
            ),
          )
          .toList(),
    ),
  );
}

class _Estado extends StatelessWidget {
  const _Estado({required this.icon, required this.texto, this.accion});
  final IconData icon;
  final String texto;
  final Future<void> Function()? accion;
  @override
  Widget build(BuildContext c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: c.hg.mutedText),
          const SizedBox(height: 12),
          Text(texto, textAlign: TextAlign.center),
          if (accion != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: accion,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _LineChart extends StatefulWidget {
  const _LineChart({required this.puntos, required this.dinero});
  final List<PuntoMensual> puntos;
  final String Function(double) dinero;
  @override
  State<_LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<_LineChart> {
  int? _indice;
  void _seleccionar(double x, double ancho) {
    if (widget.puntos.isEmpty) return;
    final i = widget.puntos.length == 1
        ? 0
        : ((x - 12) / (ancho - 24) * (widget.puntos.length - 1)).round().clamp(
            0,
            widget.puntos.length - 1,
          );
    if (_indice != i) setState(() => _indice = i);
  }

  @override
  Widget build(BuildContext c) {
    if (widget.puntos.isEmpty) {
      return const _Estado(
        icon: Icons.show_chart,
        texto: 'No hay datos para graficar.',
      );
    }
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _Leyenda(c.hg.burgundy, 'Ventas'),
            const SizedBox(width: 16),
            _Leyenda(c.hg.gold, 'Cobros'),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (c, k) {
              final punto = _indice == null ? null : widget.puntos[_indice!];
              return MouseRegion(
                onHover: (e) => _seleccionar(e.localPosition.dx, k.maxWidth),
                onExit: (_) => setState(() => _indice = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (e) =>
                      _seleccionar(e.localPosition.dx, k.maxWidth),
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: Size(k.maxWidth, k.maxHeight),
                        painter: _LinePainter(
                          widget.puntos,
                          c.hg.burgundy,
                          c.hg.gold,
                          Theme.of(c).colorScheme.outline,
                          c.hg.mutedText,
                        ),
                      ),
                      if (punto != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(c).colorScheme.surface,
                              border: Border.all(
                                color: Theme.of(c).colorScheme.outline,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                '${punto.etiqueta} · Ventas ${widget.dinero(punto.ventas)} · Cobros ${widget.dinero(punto.cobros)}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda(this.color, this.texto);
  final Color color;
  final String texto;
  @override
  Widget build(BuildContext c) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(texto, style: const TextStyle(fontSize: 11)),
    ],
  );
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.p, this.a, this.b, this.line, this.text);
  final List<PuntoMensual> p;
  final Color a, b, line, text;
  @override
  void paint(Canvas c, Size s) {
    const l = 12.0, r = 12.0, t = 12.0, bot = 28.0;
    final maxV = math.max(
      1,
      p.fold<double>(0, (m, e) => math.max(m, math.max(e.ventas, e.cobros))),
    );
    for (var i = 0; i < 4; i++) {
      final y = t + (s.height - t - bot) * i / 3;
      c.drawLine(
        Offset(l, y),
        Offset(s.width - r, y),
        Paint()
          ..color = line
          ..strokeWidth = .6,
      );
    }
    void serie(double Function(PuntoMensual) e, Color color) {
      final path = Path();
      for (var i = 0; i < p.length; i++) {
        final x = p.length == 1
            ? s.width / 2
            : l + (s.width - l - r) * i / (p.length - 1);
        final y = t + (s.height - t - bot) * (1 - e(p[i]) / maxV);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        c.drawCircle(Offset(x, y), 3, Paint()..color = color);
      }
      c.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
    }

    serie((e) => e.ventas, a);
    serie((e) => e.cobros, b);
    final step = math.max(1, (p.length / 8).ceil());
    for (var i = 0; i < p.length; i += step) {
      final tp = TextPainter(
        text: TextSpan(
          text: p[i].etiqueta,
          style: TextStyle(fontSize: 9, color: text),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = p.length == 1
          ? s.width / 2
          : l + (s.width - l - r) * i / (p.length - 1);
      tp.paint(
        c,
        Offset(
          (x - tp.width / 2).clamp(0, s.width - tp.width),
          s.height - bot + 8,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.datos, required this.dinero});
  final List<PromedioDia> datos;
  final String Function(double) dinero;
  @override
  Widget build(BuildContext c) => LayoutBuilder(
    builder: (c, k) {
      final maxV = math.max(
        1,
        datos.fold<double>(0, (m, e) => math.max(m, e.promedio)),
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: datos
            .map(
              (e) => Expanded(
                child: Tooltip(
                  message: '${e.dia}: ${dinero(e.promedio)}',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          e.promedio == 0 ? '' : dinero(e.promedio),
                          maxLines: 1,
                          style: TextStyle(fontSize: 8, color: c.hg.mutedText),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          height: (150 * e.promedio / maxV).clamp(2, 150),
                          decoration: BoxDecoration(
                            color: c.hg.lilac,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(e.dia, style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      );
    },
  );
}
