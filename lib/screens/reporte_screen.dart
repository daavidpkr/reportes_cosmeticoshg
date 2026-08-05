import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/fila_venta.dart';
import '../services/facturas_store.dart';
import '../services/reporte_exporter.dart';
import '../services/reportes_store.dart';
import '../services/supabase_reportes_service.dart';
import '../services/vendedores_store.dart';
import 'carga_facturas_screen.dart';

class ReporteScreen extends StatefulWidget {
  const ReporteScreen({this.onCerrarSesion, super.key});

  final VoidCallback? onCerrarSesion;

  @override
  State<ReporteScreen> createState() => _ReporteScreenState();
}

class _ReporteScreenState extends State<ReporteScreen> {
  final _facturas = FacturasStore.instance;
  final _exporter = ReporteExporter();
  final _vendedores = VendedoresStore();
  final _reportes = ReportesStore();
  final _supabaseReportes = SupabaseReportesService();
  final _focusZoom = FocusNode();
  late List<FilaVenta> _filas;
  String _filtro = '';
  String _filtroVendedor = '';
  String _filtroEstado = 'todos';
  final Map<String, String> _filtrosColumnas = {};
  String? _ordenColumna;
  bool _ordenAscendente = true;
  double _zoom = 1;
  bool _vistaGeneral = false;
  final _busquedaController = TextEditingController();
  StreamSubscription<List<Map<String, dynamic>>>? _filasSubscription;
  Timer? _busquedaFacturaTimer;
  int _versionBusqueda = 0;

  // La antigua vista al 90% es ahora la escala base (100%).
  double get _escalaReporte => _zoom * .99;

  @override
  void initState() {
    super.initState();
    _crearFilas();
    _cargarVendedores();
    _cargarReportes();
  }

  @override
  void dispose() {
    _filasSubscription?.cancel();
    _busquedaFacturaTimer?.cancel();
    _focusZoom.dispose();
    _busquedaController.dispose();
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

  Future<void> _cargarReportes() async {
    await _reportes.cargar();
    _activarReporte(_reportes.activo, guardar: false);
  }

  void _activarReporte(ReporteMensual reporte, {bool guardar = true}) {
    _reportes.activo = reporte;
    _filas = reporte.filas;
    _facturas
      ..mesPermitido = reporte.mes
      ..anioPermitido = reporte.anio
      ..cargar(reporte.facturas);
    _filtrosColumnas.clear();
    _ordenColumna = null;
    if (mounted) setState(() {});
    _escucharReporteActivo();
    if (guardar) _guardarProgreso();
  }

  void _escucharReporteActivo() {
    _filasSubscription?.cancel();
    final reporte = _reportes.activo;
    _filasSubscription = _supabaseReportes.observarFilas(reporte.nombre).listen(
      (datos) {
        if (!mounted || _reportes.activo.id != reporte.id) return;
        final porNumero = <int, FilaVenta>{
          for (final fila in _filas) fila.numero: fila,
        };
        for (final dato in datos) {
          final numero = (dato['nro_fila'] as num?)?.toInt();
          if (numero == null) continue;
          final fila = porNumero.putIfAbsent(
            numero,
            () => FilaVenta(numero: numero),
          );
          fila
            ..referencia = dato['ref_fact']?.toString() ?? ''
            ..vendedor = dato['vendedor']?.toString() ?? ''
            ..esmalte = (dato['esmaltes'] as num?)?.toInt() ?? 0;
          final abonos = dato['abonos'];
          if (abonos is List) {
            fila.abonos
              ..clear()
              ..addAll(abonos.map(
                  (valor) => Abono(valor: (valor as num?)?.toDouble() ?? 0)));
            while (fila.abonos.length < 2) {
              fila.abonos.add(Abono());
            }
          }
          if (fila.referencia.isNotEmpty) {
            _completarFacturaNube(fila, fila.referencia);
          }
        }
        _filas = porNumero.values.toList()
          ..sort((a, b) => a.numero.compareTo(b.numero));
        while (_filas.length < 15) {
          _filas.add(FilaVenta(numero: _filas.length + 1));
        }
        setState(() {});
      },
      onError: (Object error) => _mostrarErrorNube(
        'No se pudo sincronizar el reporte en tiempo real: $error',
      ),
    );
  }

  Future<void> _guardarProgreso() async {
    if (_reportes.reportes.isEmpty) return;
    _reportes.activo.filas = _filas;
    _reportes.activo.facturas = _facturas.facturas;
    await _reportes.guardar();
  }

  Future<void> _nuevoReporte() async {
    final siguiente = DateTime(_reportes.activo.anio, _reportes.activo.mes + 1);
    var mes = siguiente.month;
    final anioController = TextEditingController(text: '${siguiente.year}');
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, actualizar) => AlertDialog(
          title: const Text('Crear nuevo reporte'),
          content: SizedBox(
            width: 340,
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: mes,
                    decoration: const InputDecoration(
                      labelText: 'Mes',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text(_nombreMes(i + 1)),
                      ),
                    ),
                    onChanged: (valor) => actualizar(() => mes = valor ?? mes),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: anioController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Año',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
    final anio = int.tryParse(anioController.text);
    anioController.dispose();
    if (confirmar != true || !mounted) return;
    if (anio == null || anio < 2020 || anio > 2100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un año entre 2020 y 2100.')),
      );
      return;
    }
    if (!_reportes.crear(anio, mes)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Ese reporte mensual ya existe. Selecciónalo en la lista.'),
      ));
      return;
    }
    _activarReporte(_reportes.activo);
  }

  String _nombreMes(int mes) => const [
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
      ][mes - 1];

  void _crearFilas() {
    _filas = List.generate(15, (indice) => FilaVenta(numero: indice + 1));
  }

  void _buscarFactura(int indice, String referencia) {
    _busquedaFacturaTimer?.cancel();
    final version = ++_versionBusqueda;
    _busquedaFacturaTimer = Timer(const Duration(milliseconds: 350), () {
      _buscarFacturaAhora(indice, referencia, version);
    });
  }

  Future<void> _buscarFacturaAhora(
      int indice, String referencia, int version) async {
    final valor = referencia.trim();
    if (valor.isEmpty || indice >= _filas.length) return;
    var factura = _facturas.buscar(valor);
    try {
      factura ??= await _supabaseReportes.buscarFacturaPorRef(valor);
    } catch (error) {
      _mostrarErrorNube('No se pudo consultar la factura: $error');
      return;
    }
    if (!mounted || version != _versionBusqueda || indice >= _filas.length) {
      return;
    }
    if (factura == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Factura no encontrada')),
      );
      return;
    }
    final facturaEncontrada = factura;
    final repetida = _filas.asMap().entries.where((item) {
      return item.key != indice &&
          item.value.numeroFactura == facturaEncontrada.secuencial;
    }).firstOrNull;
    if (repetida != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'La factura ${facturaEncontrada.secuencial} ya fue agregada en la fila ${repetida.value.numero}.',
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }
    final fila = _filas[indice];
    setState(() {
      fila.referencia = valor;
      fila.cliente = facturaEncontrada.cliente;
      fila.nombreComercial = facturaEncontrada.nombreComercial;
      fila.fecha = facturaEncontrada.fecha;
      fila.numeroFactura = facturaEncontrada.secuencial;
      fila.venta = facturaEncontrada.total;
      _asegurarFilaVacia();
    });
    _guardarProgreso();
    _guardarFilaNube(fila);
  }

  Future<void> _completarFacturaNube(FilaVenta fila, String referencia) async {
    if (fila.cliente.isNotEmpty && fila.venta > 0) return;
    try {
      final factura = await _supabaseReportes.buscarFacturaPorRef(referencia);
      if (!mounted || factura == null || fila.referencia != referencia) return;
      setState(() {
        fila
          ..cliente = factura.cliente
          ..nombreComercial = factura.nombreComercial
          ..fecha = factura.fecha
          ..numeroFactura = factura.secuencial
          ..venta = factura.total;
      });
    } catch (_) {
      // El stream volverá a intentar completar la factura en la próxima emisión.
    }
  }

  Future<void> _guardarFilaNube(FilaVenta fila) async {
    try {
      await _supabaseReportes.guardarFila(fila, _reportes.activo.nombre);
    } catch (error) {
      _mostrarErrorNube('No se pudo guardar la fila ${fila.numero}: $error');
    }
  }

  void _mostrarErrorNube(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.red.shade700),
    );
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
    _guardarProgreso();
    if (resultado != null) _guardarFilaNube(fila);
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
    await _guardarProgreso();
    if (!mounted) return;
    var desde = _reportes.reportes.first.id;
    var hasta = _reportes.reportes.last.id;
    String? vendedor;
    final opcion = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, actualizar) => AlertDialog(
          title: const Text('Descargar PDF'),
          content: SizedBox(
            width: 430,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Escoja el rango del reporte'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: DropdownButtonFormField<String>(
                  initialValue: desde,
                  decoration: const InputDecoration(
                      labelText: 'Desde', border: OutlineInputBorder()),
                  items: _reportes.reportes
                      .map((r) =>
                          DropdownMenuItem(value: r.id, child: Text(r.nombre)))
                      .toList(),
                  onChanged: (v) => actualizar(() => desde = v ?? desde),
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: DropdownButtonFormField<String>(
                  initialValue: hasta,
                  decoration: const InputDecoration(
                      labelText: 'Hasta', border: OutlineInputBorder()),
                  items: _reportes.reportes
                      .map((r) =>
                          DropdownMenuItem(value: r.id, child: Text(r.nombre)))
                      .toList(),
                  onChanged: (v) => actualizar(() => hasta = v ?? hasta),
                )),
              ]),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                initialValue: vendedor,
                decoration: const InputDecoration(
                    labelText: 'Contenido', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Todos los vendedores')),
                  ..._vendedores.vendedores.map((v) =>
                      DropdownMenuItem<String?>(
                          value: v.etiqueta, child: Text(v.etiqueta))),
                ],
                onChanged: (v) => actualizar(() => vendedor = v),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.download),
              label: const Text('Descargar'),
            ),
          ],
        ),
      ),
    );
    if (opcion != true) return;
    if (desde.compareTo(hasta) > 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('El mes inicial no puede ser posterior al mes final.')),
        );
      }
      return;
    }
    final reportes = _reportes.reportes
        .where((r) => r.id.compareTo(desde) >= 0 && r.id.compareTo(hasta) <= 0)
        .toList();
    final todas = reportes.expand((r) => r.filas).toList();
    final filas = vendedor == null
        ? todas
        : todas.where((f) => f.vendedor == vendedor).toList();
    if (!filas.any((fila) => fila.tieneDatos)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No hay datos para generar este reporte.')),
      );
      return;
    }
    try {
      final ruta = await _exporter.guardar(
        filas,
        vendedor: vendedor,
        periodo: '${reportes.first.nombre} a ${reportes.last.nombre}',
        nombresVendedores: {
          for (final vendedor in _vendedores.vendedores)
            vendedor.etiqueta: vendedor.nombre,
        },
      );
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

  // Conservado para compatibilidad con el flujo de diálogo anterior.
  // ignore: unused_element
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
    final nombre = _reportes.activo.nombre;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar reporte'),
        content: Text(
          '¿Deseas eliminar completamente el reporte de $nombre? Esta acción también elimina ese mes y sus datos guardados.',
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
    _reportes.eliminarActivo();
    _filtro = '';
    _filtroVendedor = '';
    _filtroEstado = 'todos';
    _activarReporte(_reportes.activo);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Se eliminó el reporte de $nombre.')),
    );
  }

  Future<void> _eliminarReporteCliente() async {
    final candidatas = _filas.where((fila) => fila.tieneDatos).toList();
    if (candidatas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No hay reportes de clientes para eliminar.')),
      );
      return;
    }

    var seleccionada = candidatas.first;
    final elegir = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, actualizar) => AlertDialog(
          title: const Text('Eliminar reporte de un cliente'),
          content: SizedBox(
            width: 440,
            child: DropdownButtonFormField<int>(
              initialValue: seleccionada.numero,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Selecciona el cliente',
                border: OutlineInputBorder(),
              ),
              items: candidatas
                  .map((fila) => DropdownMenuItem(
                        value: fila.numero,
                        child: Text(
                          '${fila.cliente.isEmpty ? "Sin nombre" : fila.cliente} · Factura ${fila.numeroFactura.isEmpty ? fila.referencia : fila.numeroFactura}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (numero) {
                if (numero == null) return;
                actualizar(() {
                  seleccionada = candidatas.firstWhere(
                    (fila) => fila.numero == numero,
                  );
                });
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    if (elegir != true || !mounted) return;

    final cliente = seleccionada.cliente.isEmpty
        ? 'la factura ${seleccionada.numeroFactura}'
        : seleccionada.cliente;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
          '¿Deseas eliminar del reporte de ${_reportes.activo.nombre} el registro de $cliente?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      await _supabaseReportes.eliminarFila(
        seleccionada.numero,
        _reportes.activo.nombre,
      );
      if (!mounted) return;
      final indice = _filas.indexOf(seleccionada);
      setState(() => _filas[indice] = FilaVenta(numero: seleccionada.numero));
      await _guardarProgreso();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se eliminó el reporte de $cliente.')),
      );
    } catch (error) {
      _mostrarErrorNube('No se pudo eliminar el reporte de $cliente: $error');
    }
  }

  List<MapEntry<int, FilaVenta>> get _filasVisibles {
    final texto = _filtro.toLowerCase();
    final resultado = _filas.asMap().entries.where((item) {
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
    }).where((item) {
      return _filtrosColumnas.entries.every((filtro) => _valorTexto(
            item.value,
            filtro.key,
          ).toLowerCase().contains(filtro.value.toLowerCase()));
    }).toList();
    final columna = _ordenColumna;
    if (columna != null) {
      resultado.sort((a, b) {
        if (!a.value.tieneDatos && b.value.tieneDatos) return 1;
        if (a.value.tieneDatos && !b.value.tieneDatos) return -1;
        final izquierda = _valorOrden(a.value, columna);
        final derecha = _valorOrden(b.value, columna);
        final comparacion = izquierda is num && derecha is num
            ? izquierda.compareTo(derecha)
            : izquierda.toString().toLowerCase().compareTo(
                  derecha.toString().toLowerCase(),
                );
        return _ordenAscendente ? comparacion : -comparacion;
      });
    }
    return resultado;
  }

  String _valorTexto(FilaVenta fila, String columna) => switch (columna) {
        'nro' => '${fila.numero}',
        'referencia' => fila.referencia,
        'cliente' => fila.cliente,
        'nombre' => fila.nombreComercial,
        'fecha' => fila.fecha,
        'factura' => fila.numeroFactura,
        'vendedor' => fila.vendedor,
        'esmalte' => '${fila.esmalte}',
        'venta' => fila.venta.toStringAsFixed(2),
        'abono1' => fila.abonos[0].valor.toStringAsFixed(2),
        'abono2' => fila.abonos[1].valor.toStringAsFixed(2),
        'totalAbono' => fila.totalAbonos.toStringAsFixed(2),
        'saldo' => fila.saldo.toStringAsFixed(2),
        _ => '',
      };

  Object _valorOrden(FilaVenta fila, String columna) => switch (columna) {
        'nro' => fila.numero,
        'referencia' => int.tryParse(fila.referencia) ?? fila.referencia,
        'factura' => int.tryParse(fila.numeroFactura) ?? fila.numeroFactura,
        'fecha' => _fechaParaOrdenar(fila.fecha),
        'esmalte' => fila.esmalte,
        'venta' => fila.venta,
        'abono1' => fila.abonos[0].valor,
        'abono2' => fila.abonos[1].valor,
        'totalAbono' => fila.totalAbonos,
        'saldo' => fila.saldo,
        _ => _valorTexto(fila, columna),
      };

  Object _fechaParaOrdenar(String fecha) {
    final partes = RegExp(r'^(\d{1,4})[-/](\d{1,2})[-/](\d{1,4})')
        .firstMatch(fecha.trim());
    if (partes == null) return fecha;
    final primera = int.tryParse(partes.group(1)!) ?? 0;
    final mes = int.tryParse(partes.group(2)!) ?? 0;
    final tercera = int.tryParse(partes.group(3)!) ?? 0;
    final anio = partes.group(1)!.length == 4 ? primera : tercera;
    final dia = partes.group(1)!.length == 4 ? tercera : primera;
    return anio * 10000 + mes * 100 + dia;
  }

  Future<void> _filtrarColumna(String columna, String titulo) async {
    final controller = TextEditingController(text: _filtrosColumnas[columna]);
    final valor = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Filtrar $titulo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Valor que debe contener',
            prefixIcon: Icon(Icons.filter_alt),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (texto) => Navigator.pop(context, texto),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Quitar filtro'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (valor == null || !mounted) return;
    setState(() {
      if (valor.isEmpty) {
        _filtrosColumnas.remove(columna);
      } else {
        _filtrosColumnas[columna] = valor;
      }
    });
  }

  Widget _encabezado(String titulo, String columna) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titulo),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Ordenar o filtrar $titulo',
            icon: Icon(
              _filtrosColumnas.containsKey(columna)
                  ? Icons.filter_alt
                  : Icons.arrow_drop_down,
              color: Colors.white,
              size: 20,
            ),
            onSelected: (accion) {
              if (accion == 'asc' || accion == 'desc') {
                setState(() {
                  _ordenColumna = columna;
                  _ordenAscendente = accion == 'asc';
                });
              } else if (accion == 'filter') {
                _filtrarColumna(columna, titulo);
              } else {
                setState(() => _filtrosColumnas.remove(columna));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'asc', child: Text('Orden ascendente')),
              const PopupMenuItem(
                  value: 'desc', child: Text('Orden descendente')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'filter', child: Text('Filtrar…')),
              if (_filtrosColumnas.containsKey(columna))
                const PopupMenuItem(
                    value: 'clear', child: Text('Quitar filtro')),
            ],
          ),
        ],
      );

  Widget _encabezadoSinFiltro(String titulo) => Text(titulo);

  List<FilaVenta> get _filasParaTotales => _vistaGeneral
      ? _filasGenerales
      : _filasVisibles.map((item) => item.value).toList();
  int get _totalEsmaltes =>
      _filasParaTotales.fold(0, (suma, fila) => suma + fila.esmalte);
  double get _totalVentas =>
      _filasParaTotales.fold(0, (suma, fila) => suma + fila.venta);
  double get _totalCobros =>
      _filasParaTotales.fold(0, (suma, fila) => suma + fila.totalAbonos);
  double get _totalPorCobrar =>
      _filasParaTotales.fold(0, (suma, fila) => suma + fila.saldo);

  List<FilaVenta> get _filasGenerales {
    final texto = _filtro.toLowerCase();
    return _reportes.reportes.expand((r) => r.filas).where((fila) {
      if (!fila.tieneDatos) return false;
      final coincide = texto.isEmpty ||
          fila.numeroFactura.toLowerCase().contains(texto) ||
          fila.cliente.toLowerCase().contains(texto) ||
          fila.nombreComercial.toLowerCase().contains(texto) ||
          fila.vendedor.toLowerCase().contains(texto);
      if (!coincide ||
          (_filtroVendedor.isNotEmpty && fila.vendedor != _filtroVendedor)) {
        return false;
      }
      return switch (_filtroEstado) {
        'pagados' => fila.pagada,
        'pendientes' => !fila.pagada,
        _ => true,
      };
    }).toList();
  }

  // ignore: unused_element
  String get _descripcionFiltro {
    final partes = <String>[];
    if (_filtro.isNotEmpty) partes.add('Texto: $_filtro');
    if (_filtroVendedor.isNotEmpty) {
      partes.add('Vendedor: $_filtroVendedor');
    }
    if (_filtroEstado == 'pagados') partes.add('Pagados al 100%');
    if (_filtroEstado == 'pendientes') partes.add('Pendientes');
    if (_filtrosColumnas.isNotEmpty) {
      partes.add('${_filtrosColumnas.length} filtro(s) de columna');
    }
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
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: widget.onCerrarSesion,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
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
                const SizedBox(height: 10),
                _barraBusqueda(),
                const SizedBox(height: 8),
                Expanded(child: _vistaGeneral ? _tablaGeneral() : _tabla()),
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
                      .map((reporte) => DropdownMenuItem(
                            value: reporte.id,
                            child: Text(reporte.nombre),
                          ))
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
                onPressed: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CargaFacturasScreen(
                        mes: _reportes.activo.mes,
                        anio: _reportes.activo.anio,
                      ),
                    ),
                  );
                  if (mounted) {
                    setState(() {});
                    await _guardarProgreso();
                  }
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
                onPressed: _eliminarReporteCliente,
                icon: const Icon(Icons.person_remove),
                label: const Text('Eliminar reporte de cliente'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => setState(() => _vistaGeneral = !_vistaGeneral),
                icon: Icon(_vistaGeneral
                    ? Icons.calendar_view_month
                    : Icons.table_view),
                label: Text(
                    _vistaGeneral ? 'Reporte mes a mes' : 'Reporte general'),
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
                      isDense: true),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Todos')),
                    ..._vendedores.vendedores.map((v) => DropdownMenuItem(
                        value: v.etiqueta, child: Text(v.etiqueta)))
                  ],
                  onChanged: (v) => setState(() => _filtroVendedor = v ?? ''),
                )),
            SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _filtroEstado,
                  decoration: const InputDecoration(
                      labelText: 'Estado',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'todos', child: Text('Todos')),
                    DropdownMenuItem(value: 'pagados', child: Text('Pagados')),
                    DropdownMenuItem(
                        value: 'pendientes', child: Text('Pendientes')),
                  ],
                  onChanged: (v) =>
                      setState(() => _filtroEstado = v ?? 'todos'),
                )),
          ],
        ),
      );

  Widget _tabla() => Padding(
        padding: const EdgeInsets.only(left: 10),
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
                rows: _filasVisibles
                    .map((item) => _crearFila(item.key, item.value))
                    .toList(),
              ),
            ),
          ),
        ),
      );

  Widget _tablaGeneral() => Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(Colors.pink.shade800),
              headingTextStyle: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
              columns: const [
                DataColumn(label: Text('CLIENTE')),
                DataColumn(label: Text('NOMBRE COMERCIAL')),
                DataColumn(label: Text('FECHA')),
                DataColumn(label: Text('NRO. FACT.')),
                DataColumn(label: Text('VENDEDOR')),
                DataColumn(label: Text('ESMALTE')),
                DataColumn(label: Text('VENTA')),
                DataColumn(label: Text('TOT. ABONO')),
                DataColumn(label: Text('SALDO')),
              ],
              rows: _filasGenerales
                  .map((fila) => DataRow(
                        color: fila.pagada
                            ? WidgetStatePropertyAll(
                                Colors.green.withValues(alpha: .12))
                            : null,
                        cells: [
                          DataCell(Text(fila.cliente)),
                          DataCell(Text(fila.nombreComercial)),
                          DataCell(Text(fila.fecha)),
                          DataCell(Text(fila.numeroFactura)),
                          DataCell(Text(fila.vendedor)),
                          DataCell(Text('${fila.esmalte}')),
                          DataCell(Text('\$${fila.venta.toStringAsFixed(2)}')),
                          DataCell(
                              Text('\$${fila.totalAbonos.toStringAsFixed(2)}')),
                          DataCell(Text('\$${fila.saldo.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold))),
                        ],
                      ))
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
          DataCell(SizedBox(
            width: 28 * _escalaReporte,
            child: Text('${fila.numero}'),
          )),
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
        width: 82 * _escalaReporte,
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
          selectedItemBuilder: (_) => _vendedores.vendedores
              .map((item) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.codigo.isEmpty ? item.nombre : item.codigo,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: (valor) {
            setState(() => fila.vendedor = valor ?? '');
            _guardarProgreso();
            _guardarFilaNube(fila);
          },
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
          onChanged: (texto) {
            setState(() => fila.esmalte = int.tryParse(texto) ?? 0);
            _guardarProgreso();
            _guardarFilaNube(fila);
          },
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
          onChanged: alCambiar,
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
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 30,
            runSpacing: 10,
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
              Text(
                'Total por cobrar: \$${_totalPorCobrar.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.bold),
              ),
              if (!_vistaGeneral) ...[
                FilledButton.icon(
                  onPressed: _reiniciar,
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  icon: const Icon(Icons.delete),
                  label: const Text('Eliminar reporte'),
                ),
              ],
            ],
          ),
        ),
      );
}
