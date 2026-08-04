import 'package:flutter/material.dart';

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
  late List<FilaVenta> _filas;
  String _filtro = '';
  String _filtroVendedor = '';
  String _filtroEstado = 'todos';

  @override
  void initState() {
    super.initState();
    _crearFilas();
    _cargarVendedores();
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

  void _agregarAbono(FilaVenta fila) {
    setState(() => fila.abonos.add(Abono()));
    _editarAbono(fila, fila.abonos.length - 1, nuevo: true);
  }

  Future<void> _gestionarVendedores() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, actualizar) => AlertDialog(
          title: const Text('Vendedores'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del vendedor',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) async {
                          if (await _vendedores.agregar(controller.text)) {
                            controller.clear();
                            actualizar(() {});
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Guardar vendedor',
                      onPressed: () async {
                        if (await _vendedores.agregar(controller.text)) {
                          controller.clear();
                          actualizar(() {});
                        }
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
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
                        final nombre = _vendedores.vendedores[indice];
                        return ListTile(
                          dense: true,
                          title: Text(nombre),
                          trailing: IconButton(
                            tooltip: 'Eliminar',
                            onPressed: () async {
                              await _vendedores.eliminar(nombre);
                              for (final fila in _filas) {
                                if (fila.vendedor == nombre) {
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
    controller.dispose();
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
              onPressed: () => Navigator.pop(context, (vendedor: vendedor)),
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(vendedor),
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
                    labelText: 'Factura, cliente o vendedor',
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
                      (nombre) => DropdownMenuItem(
                        value: nombre,
                        child: Text(nombre),
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
      body: Padding(
        padding: const EdgeInsets.all(12),
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

  Widget _tabla() => Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(Colors.pink.shade800),
              headingTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              columns: const [
                DataColumn(label: Text('NRO')),
                DataColumn(label: Text('REF. (FACT)')),
                DataColumn(label: Text('CLIENTE')),
                DataColumn(label: Text('FECHA')),
                DataColumn(label: Text('NRO. FACT.')),
                DataColumn(label: Text('VENDEDOR')),
                DataColumn(label: Text('ESMALTE')),
                DataColumn(label: Text('VENTA')),
                DataColumn(label: Text('ABONO 1')),
                DataColumn(label: Text('ABONO 2')),
                DataColumn(label: Text('OTROS ABONOS')),
                DataColumn(label: Text('TOT. ABONO')),
                DataColumn(label: Text('SALDO')),
              ],
              rows: _filasVisibles
                  .map((item) => _crearFila(item.key, item.value))
                  .toList(),
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
            90,
            (valor) => _buscarFactura(indice, valor),
            enviar: true,
          )),
          DataCell(SizedBox(width: 180, child: Text(fila.cliente))),
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
        width: 150,
        child: DropdownButtonFormField<String>(
          initialValue: fila.vendedor.isEmpty ? null : fila.vendedor,
          isExpanded: true,
          hint: const Text('Escoger'),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: _vendedores.vendedores
              .map((nombre) => DropdownMenuItem(
                    value: nombre,
                    child: Text(nombre, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (valor) => setState(() => fila.vendedor = valor ?? ''),
        ),
      );

  Widget _entradaEntera(FilaVenta fila) => SizedBox(
        width: 75,
        child: TextFormField(
          initialValue: fila.esmalte == 0 ? '' : '${fila.esmalte}',
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            isDense: true,
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
            border: OutlineInputBorder(),
          ),
          onChanged: enviar ? null : alCambiar,
          onFieldSubmitted: enviar ? alCambiar : null,
        ),
      );

  Widget _botonAbono(FilaVenta fila, int indice) {
    final abono = fila.abonos[indice];
    return SizedBox(
      width: 100,
      child: OutlinedButton(
        onPressed: () => _editarAbono(fila, indice),
        child: Text(
          abono.valor == 0 ? 'Añadir' : '\$${abono.valor.toStringAsFixed(2)}',
        ),
      ),
    );
  }

  Widget _abonosAdicionales(FilaVenta fila) => SizedBox(
        width: 180,
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var indice = 2; indice < fila.abonos.length; indice++)
              OutlinedButton(
                onPressed: () => _editarAbono(fila, indice),
                child: Text(
                  '${indice + 1}: \$${fila.abonos[indice].valor.toStringAsFixed(2)}',
                ),
              ),
            IconButton.filledTonal(
              tooltip: 'Añadir otro abono a esta fila',
              onPressed: () => _agregarAbono(fila),
              icon: const Icon(Icons.add),
            ),
          ],
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
