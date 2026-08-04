import 'package:flutter/material.dart';

import '../models/fila_venta.dart';
import '../services/facturas_store.dart';
import '../services/reporte_exporter.dart';
import 'carga_facturas_screen.dart';

class ReporteScreen extends StatefulWidget {
  const ReporteScreen({super.key});

  @override
  State<ReporteScreen> createState() => _ReporteScreenState();
}

class _ReporteScreenState extends State<ReporteScreen> {
  final _store = FacturasStore.instance;
  final _exporter = ReporteExporter();
  late List<FilaVenta> _filas;

  @override
  void initState() {
    super.initState();
    _crearFilas();
  }

  void _crearFilas() {
    _filas = List.generate(15, (indice) => FilaVenta(numero: indice + 1));
  }

  void _buscarFactura(int indice, String referencia) {
    final fila = _filas[indice];
    final valor = referencia.trim();
    final factura = _store.buscar(valor);
    setState(() {
      fila.referencia = valor;
      fila.cliente = factura?.cliente ?? (valor.isEmpty ? '' : 'NO ENCONTRADA');
      fila.fecha = factura?.fecha ?? '';
      fila.numeroFactura = factura?.secuencial ?? valor;
      fila.venta = factura?.total ?? 0;
    });
  }

  Future<void> _reiniciar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar reporte'),
        content: const Text(
            '¿Deseas vaciar el reporte y eliminar las facturas cargadas?'),
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
      _store.limpiar();
      _crearFilas();
    });
  }

  Future<void> _guardar() async {
    try {
      final ruta = await _exporter.guardar(_filas);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('PDF guardado en: $ruta')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el reporte: $error')),
      );
    }
  }

  double get _totalVentas => _filas.fold(0, (suma, fila) => suma + fila.venta);
  double get _totalCobros =>
      _filas.fold(0, (suma, fila) => suma + fila.totalAbonos);
  double get _totalEsmaltes =>
      _filas.fold(0, (suma, fila) => suma + fila.esmalte);

  Future<void> _editarAbono(FilaVenta fila, int numero) async {
    final montoActual = numero == 1 ? fila.abono1 : fila.abono2;
    final comentarioActual = numero == 1 ? fila.comentario1 : fila.comentario2;
    final montoController = TextEditingController(
      text: montoActual == 0 ? '' : montoActual.toStringAsFixed(2),
    );
    final comentarioController = TextEditingController(text: comentarioActual);
    final resultado = await showDialog<(double, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Abono $numero'),
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
                  hintText: 'Ejemplo: recibo, fecha o forma de pago',
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
            onPressed: () {
              final monto = double.tryParse(
                    montoController.text.trim().replaceAll(',', '.'),
                  ) ??
                  0;
              Navigator.pop(
                context,
                (monto, comentarioController.text.trim()),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    montoController.dispose();
    comentarioController.dispose();
    if (resultado == null || !mounted) return;
    setState(() {
      if (numero == 1) {
        fila.abono1 = resultado.$1;
        fila.comentario1 = resultado.$2;
      } else {
        fila.abono2 = resultado.$1;
        fila.comentario2 = resultado.$2;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('COSMÉTICOS HG - REPORTE DE VENTAS',
            style: TextStyle(fontSize: 16)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _barraAcciones(),
            const SizedBox(height: 10),
            Expanded(child: _tabla()),
            const SizedBox(height: 10),
            _totales(),
          ],
        ),
      ),
    );
  }

  Widget _barraAcciones() {
    return Card(
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
                      builder: (_) => const CargaFacturasScreen()),
                );
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.upload_file),
              label: Text('Subir facturas (${_store.cantidad})'),
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
  }

  Widget _tabla() {
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(Colors.pink.shade800),
            headingTextStyle: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
            columns: const [
              DataColumn(label: Text('NRO')),
              DataColumn(label: Text('REF. (FACT)')),
              DataColumn(label: Text('CLIENTE')),
              DataColumn(label: Text('FECHA')),
              DataColumn(label: Text('NRO. FACT.')),
              DataColumn(label: Text('ESMALTE')),
              DataColumn(label: Text('VENTA')),
              DataColumn(label: Text('ABONO 1')),
              DataColumn(label: Text('ABONO 2')),
              DataColumn(label: Text('TOT. ABONO')),
              DataColumn(label: Text('SALDO')),
            ],
            rows: List.generate(_filas.length, _crearFila),
          ),
        ),
      ),
    );
  }

  DataRow _crearFila(int indice) {
    final fila = _filas[indice];
    return DataRow(
      key: ValueKey(fila.numero),
      cells: [
        DataCell(Text('${fila.numero}')),
        DataCell(_entrada(
            fila.referencia, 90, (valor) => _buscarFactura(indice, valor),
            enviar: true)),
        DataCell(SizedBox(width: 180, child: Text(fila.cliente))),
        DataCell(Text(fila.fecha)),
        DataCell(Text(fila.numeroFactura)),
        DataCell(_numero(
          fila.esmalte,
          (valor) => setState(() => fila.esmalte = valor),
        )),
        DataCell(Text('\$${fila.venta.toStringAsFixed(2)}')),
        DataCell(_botonAbono(fila, 1)),
        DataCell(_botonAbono(fila, 2)),
        DataCell(Text('\$${fila.totalAbonos.toStringAsFixed(2)}')),
        DataCell(Text('\$${fila.saldo.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold))),
      ],
    );
  }

  Widget _entrada(String valor, double ancho, ValueChanged<String> alCambiar,
      {bool enviar = false}) {
    return SizedBox(
      width: ancho,
      child: TextFormField(
        initialValue: valor,
        decoration:
            const InputDecoration(isDense: true, border: OutlineInputBorder()),
        onChanged: enviar ? null : alCambiar,
        onFieldSubmitted: enviar ? alCambiar : null,
      ),
    );
  }

  Widget _numero(double valor, ValueChanged<double> alCambiar) {
    return SizedBox(
      width: 75,
      child: TextFormField(
        initialValue: valor == 0 ? '' : valor.toStringAsFixed(2),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration:
            const InputDecoration(isDense: true, border: OutlineInputBorder()),
        onChanged: (texto) =>
            alCambiar(double.tryParse(texto.replaceAll(',', '.')) ?? 0),
      ),
    );
  }

  Widget _botonAbono(FilaVenta fila, int numero) {
    final monto = numero == 1 ? fila.abono1 : fila.abono2;
    return SizedBox(
      width: 100,
      child: OutlinedButton(
        onPressed: () => _editarAbono(fila, numero),
        child: Text(monto == 0 ? 'Añadir' : '\$${monto.toStringAsFixed(2)}'),
      ),
    );
  }

  Widget _totales() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 30,
          children: [
            Text('Total esmaltes: ${_totalEsmaltes.toStringAsFixed(2)}'),
            Text('Total ventas: \$${_totalVentas.toStringAsFixed(2)}'),
            Text(
              'Total cobros: \$${_totalCobros.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Colors.green, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
