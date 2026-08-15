// ignore_for_file: invalid_use_of_protected_member, unused_element

part of '../reporte_screen.dart';

extension _ReporteScreenView on _ReporteScreenState {
  Widget _totales() => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 30,
            runSpacing: 10,
            children: [
              Text('Total esmaltes: $_totalEsmaltes'),
              Text('Total ventas: \$${_totalVentas.toStringAsFixed(2)}'),
              Text(
                'Total cobros: \$${_totalCobros.toStringAsFixed(2)}',
                style: TextStyle(
                  color: context.hg.positive,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Total por cobrar: \$${_totalPorCobrar.toStringAsFixed(2)}',
                style: TextStyle(
                  color: context.hg.warning,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!_vistaGeneral) ...[
                FilledButton.icon(
                  onPressed: _reiniciar,
                  style: FilledButton.styleFrom(
                      backgroundColor: context.hg.danger),
                  icon: const Icon(Icons.delete),
                  label: const Text('Eliminar reporte'),
                ),
              ],
            ],
          ),
        ),
      );
  Widget _abonosAdicionales(FilaVenta fila) => SizedBox(
        width: 42 * _escalaReporte,
        child: IconButton.filledTonal(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          tooltip: fila.abonos.length > 2
              ? 'Ver o añadir abonos (${fila.abonos.length - 2})'
              : 'Añadir otro abono a esta fila',
          onPressed: () => _gestionarAbonosAdicionales(fila),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.add, size: 20 * _escalaReporte),
              if (fila.abonos.length > 2)
                Positioned(
                  right: -9,
                  top: -9,
                  child: CircleAvatar(
                    radius: 8,
                    child: Text(
                      '${fila.abonos.length - 2}',
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _botonAbono(FilaVenta fila, int indice) {
    final abono = fila.abonos[indice];
    return Tooltip(
      message: abono.valor == 0
          ? 'Añadir abono'
          : 'Número de recibo: '
              '${abono.numeroRecibo?.toString() ?? 'Sin número de recibo (registro histórico)'}\n'
              'Comentario: ${abono.comentario.isEmpty ? 'Sin comentario' : abono.comentario}',
      child: SizedBox(
        width: 82 * _escalaReporte,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 6 * _escalaReporte),
            visualDensity: VisualDensity.compact,
            textStyle: TextStyle(fontSize: 14 * _escalaReporte),
          ),
          onPressed: () => _editarAbono(fila, indice),
          child: Text(
            abono.valor == 0 ? 'Añadir' : '\$${abono.valor.toStringAsFixed(2)}',
          ),
        ),
      ),
    );
  }

  Widget _entrada(
    String valor,
    double ancho,
    ValueChanged<String> alCambiar, {
    bool enviar = false,
  }) =>
      SizedBox(
        width: ancho,
        child: TextFormField(
          initialValue: valor,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 7, vertical: 10),
            border: OutlineInputBorder(),
          ),
          onChanged: alCambiar,
          onFieldSubmitted: enviar ? alCambiar : null,
        ),
      );

  String _refSinCeros(String valor) {
    final limpio = valor.trim();
    if (limpio.isEmpty) return '';

    final numero = int.tryParse(limpio);
    return numero?.toString() ?? limpio;
  }

  Widget _entradaEntera(FilaVenta fila) => SizedBox(
        width: 58 * _escalaReporte,
        child: TextFormField(
          initialValue: fila.esmalte == 0 ? '' : '${fila.esmalte}',
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 7, vertical: 10),
            border: OutlineInputBorder(),
          ),
          onChanged: (texto) {
            setState(() {
              fila.esmalte = int.tryParse(texto) ?? 0;
              _asegurarFilaVacia();
            });
            _guardarProgreso();
            _guardarFilaNube(fila);
          },
        ),
      );

  Widget _selectorVendedor(FilaVenta fila) => SizedBox(
        width: 106 * _escalaReporte,
        child: DropdownButtonFormField<String>(
          initialValue: fila.vendedor.isEmpty ? null : fila.vendedor,
          isExpanded: true,
          icon: const SizedBox.shrink(),
          hint: const Text('Escoger'),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            border: OutlineInputBorder(),
          ),
          items: _vendedores.vendedores
              .map(
            (item) => DropdownMenuItem<String>(
              value: item.etiqueta,
              child: Text(item.etiqueta, overflow: TextOverflow.ellipsis),
            ),
          )
              .followedBy(const [
            DropdownMenuItem<String>(
              value: _ReporteScreenState._opcionAnulada,
              child: Text(_ReporteScreenState._opcionAnulada),
            ),
          ]).toList(),
          selectedItemBuilder: (_) => _vendedores.vendedores
              .map<Widget>(
            (item) => Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  item.codigo.isEmpty ? item.nombre : item.codigo,
                  maxLines: 1,
                ),
              ),
            ),
          )
              .followedBy(const [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_ReporteScreenState._opcionAnulada),
            ),
          ]).toList(),
          onChanged: (valor) {
            setState(() {
              fila.vendedor = valor ?? '';
              _asegurarFilaVacia();
            });
            _guardarProgreso();
            _guardarFilaNube(fila);
          },
        ),
      );

  Widget _abonosAdicionalesLectura(FilaVenta fila) {
    if (fila.abonos.length <= 2) return const SizedBox.shrink();
    return Tooltip(
      message: fila.abonos.skip(2).indexed.map((item) {
        return 'Abono ${item.$1 + 3}: \$${item.$2.valor.toStringAsFixed(2)}';
      }).join('\n'),
      child: Chip(label: Text('+${fila.abonos.length - 2}')),
    );
  }

  DataRow _crearFila(int indice, FilaVenta fila) => DataRow(
        key: ValueKey(fila.numero),
        color: fila.anulada
            ? WidgetStatePropertyAll(context.hg.danger.withValues(alpha: 0.12))
            : fila.pagada
                ? WidgetStatePropertyAll(
                    context.hg.positive.withValues(alpha: 0.12))
                : null,
        cells: [
          DataCell(
            Container(
              width: 24 * _escalaReporte,
              height: 24 * _escalaReporte,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${fila.numero}',
                style: TextStyle(
                  color: context.hg.plum,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          DataCell(
            _entrada(
              _refSinCeros(fila.referencia),
              72 * _escalaReporte,
              (valor) => _cambiarReferencia(fila, valor),
              enviar: true,
            ),
          ),
          DataCell(
            SizedBox(width: 240 * _escalaReporte, child: Text(fila.cliente)),
          ),
          DataCell(
            SizedBox(
              width: 220 * _escalaReporte,
              child: Text(fila.nombreComercial),
            ),
          ),
          DataCell(Text(fila.fecha)),
          DataCell(Text(fila.numeroFactura)),
          DataCell(_selectorVendedor(fila)),
          DataCell(_entradaEntera(fila)),
          DataCell(Text(
              fila.anulada ? 'ANULADA' : '\$${fila.venta.toStringAsFixed(2)}')),
          DataCell(_botonAbono(fila, 0)),
          DataCell(_botonAbono(fila, 1)),
          DataCell(_abonosAdicionales(fila)),
          DataCell(Text(fila.anulada
              ? 'ANULADA'
              : '\$${fila.totalAbonos.toStringAsFixed(2)}')),
          DataCell(
            Text(
              fila.anulada ? 'ANULADA' : '\$${fila.saldo.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );

  Widget _tablaGeneral() => Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: _tablaCompartida(
              filas: _filasGenerales.map(_crearFilaLectura).toList(),
            ),
          ),
        ),
      );

  DataTable _tablaCompartida({required List<DataRow> filas}) => DataTable(
        horizontalMargin: 7 * _escalaReporte,
        columnSpacing: 13 * _escalaReporte,
        dataRowMinHeight: 38 * _escalaReporte,
        dataRowMaxHeight: 58 * _escalaReporte,
        headingRowHeight: 46 * _escalaReporte,
        headingRowColor: WidgetStatePropertyAll(context.hg.tableHeader),
        headingTextStyle: TextStyle(
          color: context.hg.mutedText,
          fontWeight: FontWeight.w600,
          letterSpacing: .7,
          fontSize: 11 * _escalaReporte,
        ),
        dataTextStyle: TextStyle(fontSize: 15 * _escalaReporte),
        columns: [
          DataColumn(label: _encabezadoSinFiltro('NRO')),
          DataColumn(label: _encabezadoSinFiltro('REF. (FACT)')),
          DataColumn(label: _encabezado('CLIENTE', 'cliente')),
          DataColumn(label: _encabezado('NOMBRE COMERCIAL', 'nombre')),
          DataColumn(label: _encabezado('FECHA', 'fecha')),
          DataColumn(label: _encabezado('NRO. FACT.', 'factura')),
          DataColumn(label: _encabezado('VENDEDOR', 'vendedor')),
          DataColumn(label: _encabezadoSinFiltro('ESMALTE')),
          DataColumn(label: _encabezado('VENTA', 'venta')),
          DataColumn(label: _encabezadoSinFiltro('ABONO 1')),
          DataColumn(label: _encabezadoSinFiltro('ABONO 2')),
          const DataColumn(label: SizedBox.shrink()),
          DataColumn(label: _encabezadoSinFiltro('TOT. ABONO')),
          DataColumn(label: _encabezado('SALDO', 'saldo')),
        ],
        rows: filas,
      );

  DataRow _crearFilaLectura(FilaVenta fila) => DataRow(
        key: ValueKey('general-${fila.referencia}-${fila.numero}'),
        color: fila.anulada
            ? WidgetStatePropertyAll(context.hg.danger.withValues(alpha: .12))
            : fila.pagada
                ? WidgetStatePropertyAll(
                    context.hg.positive.withValues(alpha: .12),
                  )
                : null,
        cells: [
          DataCell(SizedBox(
            width: 24 * _escalaReporte,
            child: Text('${fila.numero}', textAlign: TextAlign.center),
          )),
          DataCell(SizedBox(
            width: 72 * _escalaReporte,
            child: Text(_refSinCeros(fila.referencia)),
          )),
          DataCell(
              SizedBox(width: 240 * _escalaReporte, child: Text(fila.cliente))),
          DataCell(SizedBox(
            width: 220 * _escalaReporte,
            child: Text(fila.nombreComercial),
          )),
          DataCell(Text(fila.fecha)),
          DataCell(Text(fila.numeroFactura)),
          DataCell(SizedBox(
              width: 106 * _escalaReporte, child: Text(fila.vendedor))),
          DataCell(Text('${fila.esmalte}')),
          DataCell(Text(
              fila.anulada ? 'ANULADA' : '\$${fila.venta.toStringAsFixed(2)}')),
          DataCell(Text('\$${fila.abonos[0].valor.toStringAsFixed(2)}')),
          DataCell(Text('\$${fila.abonos[1].valor.toStringAsFixed(2)}')),
          DataCell(_abonosAdicionalesLectura(fila)),
          DataCell(Text(fila.anulada
              ? 'ANULADA'
              : '\$${fila.totalAbonos.toStringAsFixed(2)}')),
          DataCell(Text(
            fila.anulada ? 'ANULADA' : '\$${fila.saldo.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          )),
        ],
      );

  Widget _tabla() => Padding(
        padding: EdgeInsets.zero,
        child: Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _tablaCompartida(
                    filas: _filasVisibles
                        .map((item) => _crearFila(item.key, item.value))
                        .toList(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 28, 12),
                    child: FilledButton.icon(
                      onPressed: _reiniciar,
                      style: FilledButton.styleFrom(
                        backgroundColor: context.hg.danger,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Eliminar reporte'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _barraBusqueda() => LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: constraints.maxWidth >= 850
                  ? constraints.maxWidth - 386
                  : constraints.maxWidth,
              child: TextField(
                controller: _busquedaController,
                onChanged: (valor) => setState(() => _filtro = valor.trim()),
                decoration: InputDecoration(
                  hintText:
                      'Buscar factura, cliente, nombre comercial o vendedor',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _filtro.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          onPressed: () {
                            _busquedaController.clear();
                            setState(() => _filtro = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _filtroVendedor,
                decoration: const InputDecoration(
                  labelText: 'Vendedor',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Todos')),
                  const DropdownMenuItem(
                    value: _ReporteScreenState._opcionAnulada,
                    child: Text(_ReporteScreenState._opcionAnulada),
                  ),
                  ..._vendedores.vendedores.map(
                    (v) => DropdownMenuItem(
                      value: v.etiqueta,
                      child: Text(v.etiqueta),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _filtroVendedor = v ?? ''),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _filtroEstado,
                decoration: const InputDecoration(
                  labelText: 'Estado',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'todos', child: Text('Todos')),
                  DropdownMenuItem(value: 'pagados', child: Text('Pagados')),
                  DropdownMenuItem(
                      value: 'pendientes', child: Text('Pendientes')),
                ],
                onChanged: (v) => setState(() => _filtroEstado = v ?? 'todos'),
              ),
            ),
          ],
        ),
      );

  Widget _botonZoom() => PopupMenuButton<double>(
        tooltip: 'Cambiar zoom del reporte',
        initialValue: _zoom,
        onSelected: (valor) => setState(() => _zoom = valor),
        itemBuilder: (_) => const [
          PopupMenuItem(value: .65, child: Text('65%')),
          PopupMenuItem(value: .75, child: Text('75%')),
          PopupMenuItem(value: .85, child: Text('85%')),
          PopupMenuItem(value: 1, child: Text('100%')),
          PopupMenuItem(value: 1.15, child: Text('115%')),
          PopupMenuItem(value: 1.25, child: Text('125%')),
        ],
        child: const Tooltip(
          message: 'Zoom',
          child:
              Padding(padding: EdgeInsets.all(10), child: Icon(Icons.zoom_in)),
        ),
      );

  Widget _barraAcciones() => Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue:
                      _reportes.reportes.isEmpty ? null : _reportes.activo.id,
                  decoration: const InputDecoration(
                    labelText: 'Reporte mensual',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _reportes.reportes
                      .map(
                        (reporte) => DropdownMenuItem(
                          value: reporte.id,
                          child: Text(reporte.nombre),
                        ),
                      )
                      .toList(),
                  onChanged: (id) async {
                    if (id == null) return;
                    await _guardarProgreso();
                    _activarReporte(
                      _reportes.reportes.firstWhere((e) => e.id == id),
                    );
                  },
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _reportes.reportes.isEmpty ? null : _nuevoReporte,
                icon: const Icon(Icons.calendar_month),
                label: const Text('Nuevo mes'),
              ),
              FilledButton.tonalIcon(
                onPressed: _abrirCargaFacturas,
                icon: const Icon(Icons.upload_file),
                label: Text('Subir facturas (${_facturas.cantidad})'),
              ),
              FilledButton.tonalIcon(
                onPressed: _gestionarVendedores,
                icon: const Icon(Icons.person_add),
                label: const Text('Vendedores'),
              ),
              FilledButton.tonalIcon(
                onPressed: _eliminarReporteCliente,
                icon: const Icon(Icons.person_remove),
                label: const Text('Eliminar reporte de cliente'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => setState(() => _vistaGeneral = !_vistaGeneral),
                icon: Icon(
                  _vistaGeneral ? Icons.calendar_view_month : Icons.table_view,
                ),
                label: Text(
                  _vistaGeneral ? 'Reporte mes a mes' : 'Reporte general',
                ),
              ),
              _botonZoom(),
              FilledButton.icon(
                onPressed: _guardar,
                icon: const Icon(Icons.download),
                label: const Text('Descargar PDF'),
              ),
            ],
          ),
        ),
      );

  Widget _tarjetaTabla() => Container(
        decoration: BoxDecoration(
          color: context.hg.panel,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: _vistaGeneral ? _tablaGeneral() : _tabla(),
      );

  // Conservada como referencia del flujo compacto anterior.
  Widget _botonBarra(
    IconData icono,
    String texto,
    VoidCallback? accion, {
    bool borde = false,
  }) =>
      OutlinedButton.icon(
        onPressed: accion,
        icon: Icon(icono, size: 17),
        label: Text(texto),
        style: OutlinedButton.styleFrom(
          backgroundColor: borde
              ? Colors.white
              : Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: context.hg.plum,
          side: BorderSide(
            color: borde
                ? Theme.of(context).colorScheme.outlineVariant
                : Colors.transparent,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        ),
      );

  Widget _filtroEstadoRedisenado() => SizedBox(
        width: 130,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _filtroEstado,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          items: const [
            DropdownMenuItem(value: 'todos', child: Text('Estado: Todos')),
            DropdownMenuItem(value: 'pagados', child: Text('Pagados')),
            DropdownMenuItem(value: 'pendientes', child: Text('Pendientes')),
          ],
          onChanged: (v) => setState(() => _filtroEstado = v ?? 'todos'),
        ),
      );

  Widget _filtroVendedorRedisenado() => SizedBox(
        width: 145,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _filtroVendedor,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Vendedor: Todos')),
            const DropdownMenuItem(
              value: _ReporteScreenState._opcionAnulada,
              child: Text(_ReporteScreenState._opcionAnulada),
            ),
            ..._vendedores.vendedores.map(
              (v) =>
                  DropdownMenuItem(value: v.etiqueta, child: Text(v.etiqueta)),
            ),
          ],
          onChanged: (v) => setState(() => _filtroVendedor = v ?? ''),
        ),
      );

  Widget _campoBusquedaRedisenado() => TextField(
        controller: _busquedaController,
        onChanged: (v) => setState(() => _filtro = v.trim()),
        decoration: InputDecoration(
          hintText: 'Buscar factura, cliente, nombre comercial o vendedor',
          prefixIcon: const Icon(Icons.search, size: 19),
          suffixIcon: _filtro.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _busquedaController.clear();
                    setState(() => _filtro = '');
                  },
                  icon: const Icon(Icons.close, size: 18),
                ),
          filled: true,
          fillColor: context.hg.input,
          isDense: true,
        ),
      );

  Future<void> _guardarResumenMensual() async {
    await _guardarProgreso();
    if (!mounted) return;
    final filas = _filas.where((fila) => fila.tieneDatos).toList();
    if (filas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos para generar el reporte.')),
      );
      return;
    }
    try {
      final ruta = await _exporter.guardarResumenMensual(
        filas,
        periodo: _reportes.activo.nombre,
        nombresVendedores: {
          for (final vendedor in _vendedores.vendedores)
            vendedor.etiqueta: vendedor.nombre,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reporte mensual guardado en: $ruta')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('No se pudo guardar el reporte mensual: $error')),
      );
    }
  }

  void _abrirCargaFacturas() => setState(() {
        _vistaCargaFacturas = true;
        _vistaCalendario = false;
        _vistaGeneral = false;
        _vistaCobrosMensuales = false;
        _vistaEstadisticas = false;
        _vistaVendedores = false;
        _vistaClientes = false;
      });

  Widget _barraRedisenada() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: context.hg.panel,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(child: _campoBusquedaRedisenado()),
            const SizedBox(width: 10),
            _filtroVendedorRedisenado(),
            const SizedBox(width: 10),
            _filtroEstadoRedisenado(),
            const SizedBox(width: 10),
            _botonBarra(
              Icons.upload_file,
              'Subir facturas (${_facturas.cantidad})',
              _abrirCargaFacturas,
            ),
            const SizedBox(width: 8),
            _botonBarra(
              Icons.person_remove_outlined,
              'Eliminar cliente',
              _eliminarReporteCliente,
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _guardar,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Descargar PDF'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _guardarResumenMensual,
              icon: const Icon(Icons.analytics_outlined, size: 18),
              label: const Text('Generar reporte mensual'),
            ),
            _botonZoom(),
          ],
        ),
      );

  Widget _kpi(
    String titulo,
    String valor,
    IconData icono,
    Color color,
    Color fondo, {
    bool ultimo = false,
  }) =>
      Expanded(
        child: Container(
          margin: EdgeInsets.only(right: ultimo ? 0 : 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: fondo,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: fondo == context.hg.panel
                  ? Theme.of(context).colorScheme.outlineVariant
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.1,
                        color: context.hg.mutedText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      valor,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icono, size: 17, color: color),
              ),
            ],
          ),
        ),
      );

  Widget _tarjetasResumen() => Row(
        children: [
          _kpi(
            'TOTAL ESMALTES',
            '$_totalEsmaltes',
            Icons.brush_outlined,
            context.hg.plum,
            context.hg.panel,
          ),
          _kpi(
            'TOTAL VENTAS',
            '\$${_totalVentas.toStringAsFixed(2)}',
            Icons.payments_outlined,
            context.hg.burgundy,
            context.hg.panel,
          ),
          _kpi(
            'TOTAL COBROS',
            '\$${_totalCobros.toStringAsFixed(2)}',
            Icons.check_circle_outline,
            context.hg.positive,
            context.hg.positiveContainer,
          ),
          _kpi(
            'POR COBRAR',
            '\$${_totalPorCobrar.toStringAsFixed(2)}',
            Icons.schedule,
            context.hg.warning,
            context.hg.warningContainer,
            ultimo: true,
          ),
        ],
      );

  Widget _encabezadoPagina() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _vistaGeneral ? 'Reporte general' : 'Reporte de ventas',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _vistaGeneral
                    ? 'Consolidado de ventas y cobros de todos los meses'
                    : 'Registro mensual de facturas, abonos y saldos por cliente',
                style: TextStyle(fontSize: 12.5, color: context.hg.mutedText),
              ),
            ],
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _nuevoReporte,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nuevo mes'),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue:
                  _reportes.reportes.isEmpty ? null : _reportes.activo.id,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.calendar_month, size: 19),
                isDense: true,
              ),
              items: _reportes.reportes
                  .map(
                    (r) => DropdownMenuItem(
                      value: r.id,
                      child: Text(
                        r.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (id) async {
                if (id == null) return;
                await _guardarProgreso();
                _activarReporte(
                    _reportes.reportes.firstWhere((r) => r.id == id));
              },
            ),
          ),
        ],
      );

  Widget _pestana(String texto, bool activa, VoidCallback accion) => TextButton(
        onPressed: accion,
        style: TextButton.styleFrom(
          foregroundColor: activa ? Colors.white : Colors.white70,
          backgroundColor:
              activa ? Colors.white.withValues(alpha: .14) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: activa ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      );

  Widget _barraSuperior() => Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: const BoxDecoration(
          gradient:
              LinearGradient(colors: [Color(0xFF591530), Color(0xFF3D1A4A)]),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFC9A24C),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Text(
                'HG',
                style: TextStyle(
                  color: Color(0xFF591530),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cosméticos HG',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'P E R F E C T  N A I L S',
                  style: TextStyle(color: Color(0xFFF1E4C0), fontSize: 8),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _pestana(
                      'Reporte de ventas',
                      !_vistaGeneral &&
                          !_vistaCobrosMensuales &&
                          !_vistaEstadisticas &&
                          !_vistaVendedores &&
                          !_vistaClientes &&
                          !_vistaCalendario &&
                          !_vistaCargaFacturas,
                      _mostrarReporteVentas,
                    ),
                    _pestana(
                      'Reporte general',
                      _vistaGeneral &&
                          !_vistaCobrosMensuales &&
                          !_vistaEstadisticas &&
                          !_vistaVendedores &&
                          !_vistaClientes,
                      () => setState(() {
                        _vistaCalendario = false;
                        _vistaCargaFacturas = false;
                        _vistaGeneral = true;
                        _vistaCobrosMensuales = false;
                        _vistaEstadisticas = false;
                        _vistaVendedores = false;
                        _vistaClientes = false;
                      }),
                    ),
                    _pestana(
                      'Reporte de Cobros Mensuales',
                      _vistaCobrosMensuales,
                      () => setState(() {
                        _vistaCalendario = false;
                        _vistaCargaFacturas = false;
                        _vistaCobrosMensuales = true;
                        _vistaEstadisticas = false;
                        _vistaVendedores = false;
                        _vistaClientes = false;
                      }),
                    ),
                    _pestana(
                      'Clientes',
                      _vistaClientes,
                      () => setState(() {
                        _vistaCalendario = false;
                        _vistaCargaFacturas = false;
                        _vistaClientes = true;
                        _vistaCobrosMensuales = false;
                        _vistaEstadisticas = false;
                        _vistaVendedores = false;
                        _vistaGeneral = false;
                        _seccionMovil = 3;
                      }),
                    ),
                    _pestana(
                        'Vendedores', _vistaVendedores, _gestionarVendedores),
                    _pestana(
                      'Estadísticas',
                      _vistaEstadisticas,
                      () => setState(() {
                        _vistaCalendario = false;
                        _vistaCargaFacturas = false;
                        _vistaEstadisticas = true;
                        _vistaCobrosMensuales = false;
                        _vistaVendedores = false;
                        _vistaClientes = false;
                      }),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Calendario de cobros',
              onPressed: _abrirRecordatorios,
              style: IconButton.styleFrom(
                backgroundColor: _vistaCalendario
                    ? Colors.white.withValues(alpha: .18)
                    : null,
              ),
              icon: Icon(
                Icons.calendar_month_outlined,
                color: _vistaCalendario ? Colors.white : Colors.white70,
              ),
            ),
            IconButton(
              tooltip: 'Actualizar datos',
              onPressed: _actualizando ? null : _actualizarDesdeSupabase,
              icon: _actualizando
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh, color: Colors.white70),
            ),
            IconButton(
              tooltip: widget.modoOscuro ? 'Modo claro' : 'Modo oscuro',
              onPressed: widget.onCambiarTema,
              icon: Icon(
                widget.modoOscuro
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                color: Colors.white70,
              ),
            ),
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: widget.onCerrarSesion,
              icon: const Icon(Icons.logout, color: Colors.white70),
            ),
          ],
        ),
      );

  Widget _datoMovil(String etiqueta, String valor, {Color? color}) => SizedBox(
        width: 88,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              etiqueta.toUpperCase(),
              style: TextStyle(
                color: context.hg.mutedText,
                fontSize: 9,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              valor,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );

  Widget _campoEditableMovil(
    String etiqueta,
    String valor,
    String sugerencia,
    ValueChanged<String> asignar,
    FilaVenta fila,
  ) {
    if (_vistaGeneral) return _textoCampoMovil(etiqueta, valor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta.toUpperCase(),
          style: TextStyle(
            color: context.hg.mutedText,
            fontSize: 10,
            letterSpacing: .6,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          initialValue: valor,
          decoration: InputDecoration(
            hintText: sugerencia,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
          ),
          onChanged: (texto) {
            setState(() {
              asignar(texto);
              _asegurarFilaVacia();
            });
            _guardarProgreso();
            _guardarFilaNube(fila);
          },
        ),
      ],
    );
  }

  Widget _textoCampoMovil(String etiqueta, String valor) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              etiqueta.toUpperCase(),
              style: TextStyle(
                color: context.hg.mutedText,
                fontSize: 10,
                letterSpacing: .6,
              ),
            ),
            const SizedBox(height: 3),
            Text(valor, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      );

  Widget _tarjetaFilaMovil(FilaVenta fila) {
    final expandida = _filasExpandidas.contains(fila.numero);
    return Container(
      decoration: BoxDecoration(
        color: fila.anulada
            ? context.hg.danger.withValues(alpha: .12)
            : fila.pagada
                ? context.hg.positive.withValues(alpha: .12)
                : context.hg.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() {
              expandida
                  ? _filasExpandidas.remove(fila.numero)
                  : _filasExpandidas.add(fila.numero);
            }),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${fila.numero}',
                      style: TextStyle(
                        color: context.hg.plum,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fila.cliente,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          [
                            if (fila.referencia.isNotEmpty)
                              'Ref. ${_refSinCeros(fila.referencia)}',
                            if (fila.numeroFactura.isNotEmpty)
                              fila.numeroFactura,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.hg.mutedText,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        fila.anulada
                            ? 'ANULADA'
                            : '\$${fila.saldo.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: context.hg.burgundy,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'saldo',
                        style: TextStyle(
                          color: context.hg.mutedText,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expandida ? .5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 19,
                      color: context.hg.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: expandida
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _campoEditableMovil(
                    'Cliente',
                    fila.cliente,
                    'Nombre del cliente',
                    (valor) => fila.cliente = valor,
                    fila,
                  ),
                  const SizedBox(height: 12),
                  _campoEditableMovil(
                    'Nombre comercial',
                    fila.nombreComercial,
                    'Nombre comercial',
                    (valor) => fila.nombreComercial = valor,
                    fila,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _textoCampoMovil(
                          'Fecha',
                          fila.fecha.isEmpty ? '—' : fila.fecha,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _textoCampoMovil(
                          'Nro. fact.',
                          fila.numeroFactura.isEmpty ? '—' : fila.numeroFactura,
                        ),
                      ),
                    ],
                  ),
                  if (!_vistaGeneral) ...[
                    const SizedBox(height: 12),
                    Text(
                      'VENDEDOR / REFERENCIA',
                      style: TextStyle(
                        color: context.hg.mutedText,
                        fontSize: 10,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(child: _selectorVendedor(fila)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _entrada(
                            _refSinCeros(fila.referencia),
                            double.infinity,
                            (valor) => _cambiarReferencia(fila, valor),
                            enviar: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ESMALTES',
                      style: TextStyle(
                        color: context.hg.mutedText,
                        fontSize: 10,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          width: 11,
                          height: 11,
                          decoration: const BoxDecoration(
                            color: Color(0xFFC9A24C),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _entradaEntera(fila)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'VENTA',
                      style: TextStyle(
                        color: context.hg.mutedText,
                        fontSize: 10,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _entrada(
                      fila.venta == 0 ? '' : fila.venta.toStringAsFixed(2),
                      double.infinity,
                      (valor) {
                        final limpio =
                            valor.replaceAll(',', '.').replaceAll('\$', '');
                        setState(() {
                          fila.venta = double.tryParse(limpio) ?? 0;
                          _asegurarFilaVacia();
                        });
                        _guardarProgreso();
                        _guardarFilaNube(fila);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ABONOS',
                      style: TextStyle(
                        color: context.hg.mutedText,
                        fontSize: 10,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(child: _botonAbono(fila, 0)),
                        const SizedBox(width: 8),
                        Expanded(child: _botonAbono(fila, 1)),
                        _abonosAdicionales(fila),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: context.hg.tableHeader,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _datoMovil(
                          'Venta',
                          fila.anulada
                              ? 'ANULADA'
                              : '\$${fila.venta.toStringAsFixed(2)}',
                        ),
                        _datoMovil(
                          'Tot. abono',
                          fila.anulada
                              ? 'ANULADA'
                              : '\$${fila.totalAbonos.toStringAsFixed(2)}',
                          color: context.hg.positive,
                        ),
                        _datoMovil(
                          'Saldo',
                          fila.anulada
                              ? 'ANULADA'
                              : '\$${fila.saldo.toStringAsFixed(2)}',
                          color: context.hg.burgundy,
                        ),
                      ],
                    ),
                  ),
                  if (!_vistaGeneral) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _eliminarReporteCliente,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.hg.danger,
                          side: const BorderSide(color: Color(0xFFA8425A)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Eliminar este cliente',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _listaMovil() {
    final filas = _vistaGeneral
        ? _filasGenerales
        : _filasVisibles.map((item) => item.value).toList();
    if (filas.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No hay registros para mostrar.')),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      sliver: SliverList.separated(
        itemCount: filas.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, indice) => _tarjetaFilaMovil(filas[indice]),
      ),
    );
  }

  Widget _filtroEstadoMovil() => DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _filtroEstado,
        decoration: InputDecoration(
          labelText: 'Estado',
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
        ),
        items: const [
          DropdownMenuItem(value: 'todos', child: Text('Todos')),
          DropdownMenuItem(value: 'pagados', child: Text('Pagados')),
          DropdownMenuItem(value: 'pendientes', child: Text('Pendientes')),
        ],
        onChanged: (v) => setState(() => _filtroEstado = v ?? 'todos'),
      );

  Widget _filtroVendedorMovil() => DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _filtroVendedor,
        decoration: InputDecoration(
          labelText: 'Vendedor',
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todos')),
          const DropdownMenuItem(
            value: _ReporteScreenState._opcionAnulada,
            child: Text(_ReporteScreenState._opcionAnulada),
          ),
          ..._vendedores.vendedores.map(
            (v) => DropdownMenuItem(value: v.etiqueta, child: Text(v.etiqueta)),
          ),
        ],
        onChanged: (v) => setState(() => _filtroVendedor = v ?? ''),
      );

  Widget _campoBusquedaMovil() => TextField(
        controller: _busquedaController,
        onChanged: (valor) => setState(() => _filtro = valor.trim()),
        decoration: InputDecoration(
          hintText: 'Buscar factura, cliente o vendedor',
          hintStyle: TextStyle(color: context.hg.mutedText, fontSize: 13),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: context.hg.burgundy,
          ),
          suffixIcon: _filtro.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpiar búsqueda',
                  onPressed: () {
                    _busquedaController.clear();
                    setState(() => _filtro = '');
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
          filled: true,
          fillColor: context.hg.input,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      );

  Widget _controlesMoviles() => Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: context.hg.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A3D1A4A),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: _campoBusquedaMovil(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _filtroVendedorMovil()),
              const SizedBox(width: 8),
              Expanded(child: _filtroEstadoMovil()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _abrirCargaFacturas,
                  style: _estiloAccionMovil,
                  icon: const Icon(Icons.upload_file, size: 17),
                  label: Text('Subir facturas (${_facturas.cantidad})'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _guardarResumenMensual,
                  style: _estiloAccionMovil,
                  icon: const Icon(Icons.analytics_outlined, size: 17),
                  label: const Text('Reporte mensual'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _eliminarReporteCliente,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.hg.plum,
                backgroundColor: context.hg.panel,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(Icons.person_remove_outlined, size: 17),
              label: const Text('Eliminar cliente'),
            ),
          ),
        ],
      );

  ButtonStyle get _estiloAccionMovil => FilledButton.styleFrom(
        foregroundColor: context.hg.plum,
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      );

  Widget _kpiMovil(
    String titulo,
    String valor,
    IconData icono,
    Color color, {
    Color? fondo,
  }) {
    final colorFondo = fondo ?? context.hg.panel;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
      decoration: BoxDecoration(
        color: colorFondo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: fondo == null
              ? Theme.of(context).colorScheme.outlineVariant
              : Colors.transparent,
        ),
      ),
      child: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 28),
                child: Text(
                  titulo,
                  style: TextStyle(
                    color: context.hg.mutedText,
                    fontSize: 9.5,
                    letterSpacing: .8,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  valor,
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icono, size: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumenMovil() => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.75,
        children: [
          _kpiMovil(
            'TOTAL ESMALTES',
            '$_totalEsmaltes',
            Icons.brush_outlined,
            context.hg.plum,
          ),
          _kpiMovil(
            'VENTAS',
            '\$${_totalVentas.toStringAsFixed(2)}',
            Icons.payments_outlined,
            context.hg.burgundy,
          ),
          _kpiMovil(
            'COBROS',
            '\$${_totalCobros.toStringAsFixed(2)}',
            Icons.check_circle_outline,
            context.hg.positive,
            fondo: context.hg.positiveContainer,
          ),
          _kpiMovil(
            'POR COBRAR',
            '\$${_totalPorCobrar.toStringAsFixed(2)}',
            Icons.schedule,
            context.hg.warning,
            fondo: context.hg.warningContainer,
          ),
        ],
      );

  Widget _encabezadoMovil() => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _vistaGeneral ? 'Reporte general' : 'Reporte de ventas',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _vistaGeneral
                      ? 'Consolidado de todos los meses'
                      : 'Facturas, abonos y saldos por cliente',
                  style: TextStyle(color: context.hg.mutedText, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            tooltip: 'Crear nuevo mes',
            onPressed: _nuevoReporte,
            icon: const Icon(Icons.add, size: 18),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 135,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue:
                  _reportes.reportes.isEmpty ? null : _reportes.activo.id,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.calendar_month_outlined, size: 17),
                prefixIconConstraints: BoxConstraints(minWidth: 34),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                isDense: true,
              ),
              items: _reportes.reportes
                  .map((r) =>
                      DropdownMenuItem(value: r.id, child: Text(r.nombre)))
                  .toList(),
              onChanged: (id) async {
                if (id == null) return;
                await _guardarProgreso();
                _activarReporte(
                    _reportes.reportes.firstWhere((r) => r.id == id));
              },
            ),
          ),
        ],
      );

  Widget _vistaMovil() => Scaffold(
        appBar: AppBar(
          foregroundColor: Colors.white,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF591530), Color(0xFF3D1A4A)],
              ),
            ),
          ),
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: const RadialGradient(
                    center: Alignment(-.4, -.4),
                    colors: [Color(0xFFF1E4C0), Color(0xFFC9A24C)],
                  ),
                ),
                child: const Text(
                  'HG',
                  style: TextStyle(
                    color: Color(0xFF591530),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cosméticos HG',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'P E R F E C T  N A I L S',
                    style: TextStyle(
                      color: Color(0xFFF1E4C0),
                      fontSize: 8,
                      letterSpacing: .5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Calendario de cobros',
              onPressed: _abrirRecordatorios,
              style: IconButton.styleFrom(
                backgroundColor: _vistaCalendario
                    ? Colors.white.withValues(alpha: .18)
                    : null,
              ),
              icon: const Icon(Icons.calendar_month_outlined),
            ),
            IconButton(
              tooltip: 'Actualizar datos',
              onPressed: _actualizando ? null : _actualizarDesdeSupabase,
              icon: _actualizando
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: widget.modoOscuro ? 'Modo claro' : 'Modo oscuro',
              onPressed: widget.onCambiarTema,
              icon: Icon(
                widget.modoOscuro
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: IconButton.filled(
                tooltip: 'Cerrar sesión',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: .12),
                ),
                onPressed: widget.onCerrarSesion,
                icon: const Icon(Icons.logout, size: 19),
              ),
            ),
          ],
        ),
        floatingActionButton: _vistaCobrosMensuales ||
                _vistaEstadisticas ||
                _vistaVendedores ||
                _vistaClientes ||
                _vistaCalendario ||
                _vistaCargaFacturas
            ? null
            : FloatingActionButton.extended(
                onPressed: _guardar,
                backgroundColor: context.hg.burgundy,
                foregroundColor: Colors.white,
                elevation: 5,
                icon: const Icon(Icons.download, size: 19),
                label: const Text(
                  'PDF',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
        bottomNavigationBar: NavigationBar(
          height: 68,
          selectedIndex: _seccionMovil,
          indicatorColor: Theme.of(context).colorScheme.secondaryContainer,
          onDestinationSelected: (indice) {
            setState(() {
              _vistaCalendario = false;
              _vistaCargaFacturas = false;
              _seccionMovil = indice;
              _vistaCobrosMensuales = indice == 2;
              _vistaClientes = indice == 3;
              _vistaVendedores = indice == 4;
              _vistaEstadisticas = indice == 5;
              _vistaGeneral = indice == 1;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              label: 'Ventas',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              label: 'General',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              label: 'Cobros mensuales',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              label: 'Clientes',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              label: 'Vendedores',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              label: 'Estadísticas',
            ),
          ],
        ),
        body: _vistaCalendario
            ? const PaymentCalendarView()
            : _vistaCargaFacturas
                ? CargaFacturasView(
                    key: ValueKey(_reportes.activo.id),
                    mes: _reportes.activo.mes,
                    anio: _reportes.activo.anio,
                    onVolver: _mostrarReporteVentas,
                    onFacturasGuardadas: _guardarProgreso,
                  )
                : _vistaVendedores
                    ? SafeArea(child: VendedoresContent(store: _vendedores))
                    : _vistaClientes
                        ? const SafeArea(child: ClientesScreen())
                        : _vistaEstadisticas
                            ? const SafeArea(child: EstadisticasScreen())
                            : _vistaCobrosMensuales
                                ? SafeArea(
                                    child: CobrosMensualesView(
                                        key: ValueKey(_versionCobrosMensuales)),
                                  )
                                : SafeArea(
                                    child: CustomScrollView(
                                      keyboardDismissBehavior:
                                          ScrollViewKeyboardDismissBehavior
                                              .onDrag,
                                      slivers: [
                                        SliverPadding(
                                          padding: const EdgeInsets.fromLTRB(
                                              14, 16, 14, 8),
                                          sliver: SliverList.list(
                                            children: [
                                              _encabezadoMovil(),
                                              const SizedBox(height: 14),
                                              _resumenMovil(),
                                              const SizedBox(height: 14),
                                              _controlesMoviles(),
                                              const SizedBox(height: 16),
                                              Row(
                                                children: [
                                                  Text(
                                                    _vistaGeneral
                                                        ? 'Todos los registros'
                                                        : 'Clientes',
                                                    style: TextStyle(
                                                      color: context.hg.plum,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    '${_vistaGeneral ? _filasGenerales.length : _filasVisibles.length} registros',
                                                    style: TextStyle(
                                                      color:
                                                          context.hg.mutedText,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (_descripcionFiltro
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  _descripcionFiltro,
                                                  style: TextStyle(
                                                    color: context.hg.mutedText,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        _listaMovil(),
                                        SliverToBoxAdapter(
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                14, 4, 14, 110),
                                            child: Column(
                                              children: [
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: FilledButton.icon(
                                                    onPressed: _reiniciar,
                                                    style:
                                                        FilledButton.styleFrom(
                                                      backgroundColor:
                                                          context.hg.danger,
                                                      foregroundColor:
                                                          Colors.white,
                                                      padding:
                                                          const EdgeInsets.all(
                                                              13),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                      ),
                                                    ),
                                                    icon: const Icon(
                                                        Icons.delete_outline,
                                                        size: 18),
                                                    label: const Text(
                                                        'Eliminar reporte'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
      );
}
