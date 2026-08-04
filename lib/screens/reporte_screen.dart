import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/fila_venta.dart';
import '../services/facturas_store.dart';
import '../services/reporte_exporter.dart';
import '../services/vendedores_store.dart';
import 'carga_facturas_screen.dart';

class ReporteScreen extends StatefulWidget {
  const ReporteScreen({super.key});

  @override
  State<ReporteScreen> createState() => _ReporteScreenState();
}

class _ReporteScreenState extends State<ReporteScreen> {
  final _facturas = FacturasStore.instance;
  final _exporter = ReporteExporter();
  final _vendedores = VendedoresStore();
  final _focusZoom = FocusNode();
  late List<FilaVenta> _filas;
  String _filtro = '';
  String _filtroVendedor = '';
  String _filtroEstado = 'todos';
  double _zoom = 1;

  double get _escalaReporte => _zoom * 1.1;

  @override
  void initState() {
    super.initState();
    _crearFilas();
    _cargarVendedores();
  }

  @override
  void dispose() {
    _focusZoom.dispose();
    super.dispose();
  }

  void _cambiarZoom(double cambio) {
    setState(() => _zoom = (_zoom + cambio).clamp(0.65, 1.25));
  }

  KeyEventResult _atajoZoom(FocusNode node, KeyEvent evento) {
    if (evento is! KeyDownEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }
    final aumentar = evento.character == '+' ||
        evento.logicalKey == LogicalKeyboardKey.equal ||
        evento.logicalKey == LogicalKeyboardKey.add;
    final reducir = evento.character == '-' ||
        evento.logicalKey == LogicalKeyboardKey.minus;
    if (aumentar) {
      _cambiarZoom(0.1);
      return KeyEventResult.handled;
    }
    if (reducir) {
      _cambiarZoom(-0.1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _ruedaZoom(PointerSignalEvent evento) {
    if (evento is PointerScrollEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      _cambiarZoom(evento.scrollDelta.dy < 0 ? 0.1 : -0.1);
    }
  }

  Future<void> _cargarVendedores() async {
    await _vendedores.cargar();
    if (mounted) setState(() {});
  }

  void _crearFilas() {
    _filas = List.generate(15, (indice) => FilaVenta(numero: indice + 1));
  }

  void _buscarFactura(int indice, String referencia) {
    final valor = referencia.trim();
    final factura = _facturas.buscar(valor);
    if (factura != null) {
      final repetida = _filas.asMap().entries.where((item) {
        return item.key != indice &&
            item.value.numeroFactura == factura.secuencial;
      }).firstOrNull;
      if (repetida != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'La factura ${factura.secuencial} ya fue agregada en la fila ${repetida.value.numero}.',
            ),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        return;
      }
    }

    final fila = _filas[indice];
    setState(() {
      fila.referencia = valor;
      fila.cliente = factura?.cliente ?? (valor.isEmpty ? '' : 'NO ENCONTRADA');
      fila.nombreComercial = factura?.nombreComercial ?? '';
      fila.fecha = factura?.fecha ?? '';
      fila.numeroFactura = factura?.secuencial ?? valor;
      fila.venta = factura?.total ?? 0;
      _asegurarFilaVacia();
    });
  }

  void _asegurarFilaVacia() {
    if (_filas.any((fila) => !fila.tieneDatos)) return;
    _filas.add(FilaVenta(numero: _filas.length + 1));
  }

  Future<void> _editarAbono(
    FilaVenta fila,
    int indice, {
    bool nuevo = false,
  }) async {
    final abono = fila.abonos[indice];
    final montoController = TextEditingController(
      text: abono.valor == 0 ? '' : abono.valor.toStringAsFixed(2),
    );
    final comentarioController = TextEditingController(text: abono.comentario);
    final resultado = await showDialog<(double, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Abono ${indice + 1}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: montoController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Valor',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: comentarioController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Comentario',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              (
                double.tryParse(montoController.text.replaceAll(',', '.')) ?? 0,
                comentarioController.text.trim(),
              ),
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    montoController.dispose();
    comentarioController.dispose();
    if (!mounted) return;
    setState(() {
      if (resultado == null) {
        if (nuevo) fila.abonos.removeAt(indice);
      } else {
        abono.valor = resultado.$1;
        abono.comentario = resultado.$2;
      }
    });
  }

  Future<void> _agregarAbono(FilaVenta fila) async {
    setState(() => fila.abonos.add(Abono()));
    await _editarAbono(fila, fila.abonos.length - 1, nuevo: true);
  }

  Future<void> _gestionarAbonosAdicionales(FilaVenta fila) async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, actualizar) => AlertDialog(
          title: const Text('Abonos adicionales'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (fila.abonos.length == 2)
                  const Text('No hay abonos adicionales en esta fila.'),
                for (var indice = 2; indice < fila.abonos.length; indice++)
                  ListTile(
                    title: Text('Abono ${indice + 1}'),
                    subtitle: Text(
                      fila.abonos[indice].comentario.isEmpty
                          ? 'Sin comentario'
                          : fila.abonos[indice].comentario,
                    ),
                    trailing: Text(
                      '\$${fila.abonos[indice].valor.toStringAsFixed(2)}',
                    ),
                    onTap: () async {
                      await _editarAbono(fila, indice);
                      actualizar(() {});
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await _agregarAbono(fila);
                actualizar(() {});
              },
              icon: const Icon(Icons.add),
              label: const Text('Añadir abono'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _gestionarVendedores() async {
    final codigoController = TextEditingController();
    final nombreController = TextEditingController();
    Future<void> guardar(StateSetter actualizar) async {
      if (await _vendedores.agregar(
        codigoController.text,
        nombreController.text,
      )) {
        codigoController.clear();
        nombreController.clear();
        actualizar(() {});
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ingresa código y nombre. No pueden estar repetidos.',
            ),
          ),
        );
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, actualizar) => AlertDialog(
          title: const Text('Vendedores'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codigoController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Código del vendedor',
                    hintText: 'Ejemplo: V001',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: nombreController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del vendedor',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => guardar(actualizar),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Guardar vendedor',
                    onPressed: () => guardar(actualizar),
                    icon: const Icon(Icons.add),
                  ),
                ]),
                const SizedBox(height: 12),
                if (_vendedores.vendedores.isEmpty)
                  const Text('Todavía no hay vendedores guardados')
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _vendedores.vendedores.length,
                      itemBuilder: (_, indice) {
                        final vendedor = _vendedores.vendedores[indice];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            child: Text(
                              vendedor.codigo.isEmpty ? '—' : vendedor.codigo,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                          title: Text(vendedor.nombre),
                          subtitle: vendedor.codigo.isEmpty
                              ? const Text('Sin código (vendedor anterior)')
                              : Text('Código: ${vendedor.codigo}'),
                          trailing: IconButton(
                            tooltip: 'Eliminar',
                            onPressed: () async {
                              await _vendedores.eliminar(vendedor);
                              for (final fila in _filas) {
                                if (fila.vendedor == vendedor.etiqueta) {
                                  fila.vendedor = '';
                                }
                              }
                              actualizar(() {});
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
    codigoController.dispose();
    nombreController.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _guardar() async {
    final opcion = await showDialog<({String? vendedor})>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Tipo de reporte'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, (vendedor: null)),
            child: const ListTile(
              leading: Icon(Icons.groups),
              title: Text('Reporte general'),
              subtitle: Text('Incluye todos los vendedores'),
            ),
          ),
          ..._vendedores.vendedores.map(
            (vendedor) => SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(context, (vendedor: vendedor.etiqueta)),
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(vendedor.etiqueta),
                subtitle: const Text('Reporte de este vendedor'),
              ),
            ),
          ),
        ],
      ),
    );
    if (opcion == null) return;
    final filas = opcion.vendedor == null
        ? _filas
        : _filas.where((fila) => fila.vendedor == opcion.vendedor).toList();
    if (!filas.any((fila) => fila.tieneDatos)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No hay datos para generar este reporte.')),
      );
      return;
    }
    try {
      final ruta = await _exporter.guardar(_filas, vendedor: opcion.vendedor);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF guardado en: $ruta')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el reporte: $error')),
      );
    }
  }

  Future<void> _buscar() async {
    final controller = TextEditingController(text: _filtro);
    var vendedor = _filtroVendedor;
    var estado = _filtroEstado;
    final resultado =
        await showDialog<({String texto, String vendedor, String estado})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, actualizar) => AlertDialog(
          title: const Text('Buscar y filtrar reporte'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Factura, cliente, nombre comercial o vendedor',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: vendedor,
                  decoration: const InputDecoration(
                    labelText: 'Vendedor',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Todos los vendedores'),
                    ),
                    ..._vendedores.vendedores.map(
                      (item) => DropdownMenuItem(
                        value: item.etiqueta,
                        child: Text(item.etiqueta),
                      ),
                    ),
                  ],
                  onChanged: (valor) =>
                      actualizar(() => vendedor = valor ?? ''),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: estado,
                  decoration: const InputDecoration(
                    labelText: 'Estado de pago',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'todos', child: Text('Todos')),
                    DropdownMenuItem(
                      value: 'pagados',
                      child: Text('Pagados al 100%'),
                    ),
                    DropdownMenuItem(
                      value: 'pendientes',
                      child: Text('No pagados / pendientes'),
                    ),
                  ],
                  onChanged: (valor) =>
                      actualizar(() => estado = valor ?? 'todos'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                (texto: '', vendedor: '', estado: 'todos'),
              ),
              child: const Text('Limpiar filtros'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                (
                  texto: controller.text.trim(),
                  vendedor: vendedor,
                  estado: estado,
                ),
              ),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (resultado != null && mounted) {
      setState(() {
        _filtro = resultado.texto;
        _filtroVendedor = resultado.vendedor;
        _filtroEstado = resultado.estado;
      });
    }
  }

  Future<void> _reiniciar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar reporte'),
        content: const Text(
          '¿Deseas vaciar el reporte y eliminar las facturas cargadas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sí, eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    setState(() {
      _facturas.limpiar();
      _filtro = '';
      _filtroVendedor = '';
      _filtroEstado = 'todos';
      _crearFilas();
    });
  }

  Iterable<MapEntry<int, FilaVenta>> get _filasVisibles {
    final texto = _filtro.toLowerCase();
    return _filas.asMap().entries.where((item) {
      if (texto.isEmpty) return true;
      return item.value.numeroFactura.toLowerCase().contains(texto) ||
          item.value.cliente.toLowerCase().contains(texto) ||
          item.value.nombreComercial.toLowerCase().contains(texto) ||
          item.value.vendedor.toLowerCase().contains(texto);
    }).where((item) {
      if (_filtroVendedor.isNotEmpty &&
          item.value.vendedor != _filtroVendedor) {
        return false;
      }
      return switch (_filtroEstado) {
        'pagados' => item.value.pagada,
        'pendientes' => item.value.tieneDatos && !item.value.pagada,
        _ => true,
      };
    });
  }

  List<FilaVenta> get _filasParaTotales =>
      _filasVisibles.map((item) => item.value).toList();
  int get _totalEsmaltes =>
      _filasParaTotales.fold(0, (suma, fila) => suma + fila.esmalte);
  double get _totalVentas =>
      _filasParaTotales.fold(0, (suma, fila) => suma + fila.venta);
  double get _totalCobros =>
      _filasParaTotales.fold(0, (suma, fila) => suma + fila.totalAbonos);

  String get _descripcionFiltro {
    final partes = <String>[];
    if (_filtro.isNotEmpty) partes.add('Texto: $_filtro');
    if (_filtroVendedor.isNotEmpty) {
      partes.add('Vendedor: $_filtroVendedor');
    }
    if (_filtroEstado == 'pagados') partes.add('Pagados al 100%');
    if (_filtroEstado == 'pendientes') partes.add('Pendientes');
    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'COSMÉTICOS HG - REPORTE DE VENTAS',
          style: TextStyle(fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: Focus(
        focusNode: _focusZoom,
        autofocus: true,
        onKeyEvent: _atajoZoom,
        child: Listener(
          onPointerSignal: _ruedaZoom,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                _barraAcciones(),
                if (_filtro.isNotEmpty ||
                    _filtroVendedor.isNotEmpty ||
                    _filtroEstado != 'todos')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Chip(
                      label: Text(_descripcionFiltro),
                      onDeleted: () => setState(() {
                        _filtro = '';
                        _filtroVendedor = '';
                        _filtroEstado = 'todos';
                      }),
                    ),
                  ),
                const SizedBox(height: 10),
                Expanded(child: _tabla()),
                const SizedBox(height: 10),
                _totales(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _barraAcciones() => Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CargaFacturasScreen(),
                    ),
                  );
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.upload_file),
                label: Text('Subir facturas (${_facturas.cantidad})'),
              ),
              FilledButton.tonalIcon(
                onPressed: _gestionarVendedores,
                icon: const Icon(Icons.person_add),
                label: const Text('Vendedores'),
              ),
              FilledButton.tonalIcon(
                onPressed: _buscar,
                icon: const Icon(Icons.search),
                label: const Text('Buscar / filtrar'),
              ),
              _botonZoom(),
              FilledButton.icon(
                onPressed: _guardar,
                icon: const Icon(Icons.download),
                label: const Text('Descargar PDF'),
              ),
              FilledButton.icon(
                onPressed: _reiniciar,
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                icon: const Icon(Icons.delete),
                label: const Text('Eliminar reporte'),
              ),
            ],
          ),
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
        child: Chip(
          avatar: const Icon(Icons.zoom_in, size: 18),
          label: Text('Zoom ${(_zoom * 100).round()}%'),
        ),
      );

  Widget _tabla() => Padding(
        padding: const EdgeInsets.only(left: 43),
        child: Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                horizontalMargin: 7 * _escalaReporte,
                columnSpacing: 13 * _escalaReporte,
                dataRowMinHeight: 38 * _escalaReporte,
                dataRowMaxHeight: 58 * _escalaReporte,
                headingRowHeight: 46 * _escalaReporte,
                headingRowColor: WidgetStatePropertyAll(Colors.pink.shade800),
                headingTextStyle: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14 * _escalaReporte,
                ),
                dataTextStyle: TextStyle(fontSize: 15 * _escalaReporte),
                columns: const [
                  DataColumn(label: Text('NRO')),
                  DataColumn(label: Text('REF. (FACT)')),
                  DataColumn(label: Text('CLIENTE')),
                  DataColumn(label: Text('NOMBRE COMERCIAL')),
                  DataColumn(label: Text('FECHA')),
                  DataColumn(label: Text('NRO. FACT.')),
                  DataColumn(label: Text('VENDEDOR')),
                  DataColumn(label: Text('ESMALTE')),
                  DataColumn(label: Text('VENTA')),
                  DataColumn(label: Text('ABONO 1')),
                  DataColumn(label: Text('ABONO 2')),
                  DataColumn(label: SizedBox.shrink()),
                  DataColumn(label: Text('TOT. ABONO')),
                  DataColumn(label: Text('SALDO')),
                ],
                rows: _filasVisibles
                    .map((item) => _crearFila(item.key, item.value))
                    .toList(),
              ),
            ),
          ),
        ),
      );

  DataRow _crearFila(int indice, FilaVenta fila) => DataRow(
        key: ValueKey(fila.numero),
        color: fila.pagada
            ? WidgetStatePropertyAll(Colors.green.withValues(alpha: 0.12))
            : null,
        cells: [
          DataCell(Text('${fila.numero}')),
          DataCell(_entrada(
            fila.referencia,
            72 * _escalaReporte,
            (valor) => _buscarFactura(indice, valor),
            enviar: true,
          )),
          DataCell(SizedBox(
            width: 175 * _escalaReporte,
            child: Text(fila.cliente),
          )),
          DataCell(SizedBox(
            width: 155 * _escalaReporte,
            child: Text(fila.nombreComercial),
          )),
          DataCell(Text(fila.fecha)),
          DataCell(Text(fila.numeroFactura)),
          DataCell(_selectorVendedor(fila)),
          DataCell(_entradaEntera(fila)),
          DataCell(Text('\$${fila.venta.toStringAsFixed(2)}')),
          DataCell(_botonAbono(fila, 0)),
          DataCell(_botonAbono(fila, 1)),
          DataCell(_abonosAdicionales(fila)),
          DataCell(Text('\$${fila.totalAbonos.toStringAsFixed(2)}')),
          DataCell(Text(
            '\$${fila.saldo.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          )),
        ],
      );

  Widget _selectorVendedor(FilaVenta fila) => SizedBox(
        width: 125 * _escalaReporte,
        child: DropdownButtonFormField<String>(
          initialValue: fila.vendedor.isEmpty ? null : fila.vendedor,
          isExpanded: true,
          hint: const Text('Escoger'),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            border: OutlineInputBorder(),
          ),
          items: _vendedores.vendedores
              .map((item) => DropdownMenuItem(
                    value: item.etiqueta,
                    child: Text(item.etiqueta, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (valor) => setState(() => fila.vendedor = valor ?? ''),
        ),
      );

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
          onChanged: (texto) =>
              setState(() => fila.esmalte = int.tryParse(texto) ?? 0),
        ),
      );

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
          onChanged: enviar ? null : alCambiar,
          onFieldSubmitted: enviar ? alCambiar : null,
        ),
      );

  Widget _botonAbono(FilaVenta fila, int indice) {
    final abono = fila.abonos[indice];
    return SizedBox(
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
    );
  }

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

  Widget _totales() => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 30,
            children: [
              Text('Total esmaltes: $_totalEsmaltes'),
              Text('Total ventas: \$${_totalVentas.toStringAsFixed(2)}'),
              Text(
                'Total cobros: \$${_totalCobros.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
}
