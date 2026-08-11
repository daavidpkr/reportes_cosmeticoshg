import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fila_venta.dart';
import '../services/facturas_store.dart';
import '../services/reporte_exporter.dart';
import '../services/reportes_store.dart';
import '../services/supabase_reportes_service.dart';
import '../services/vendedores_store.dart';
import '../theme/hg_theme.dart';
import 'carga_facturas_screen.dart';
import 'cobros_mensuales_view.dart';
import 'clientes_screen.dart';
import 'estadisticas_screen.dart';
import 'payment_reminders_screen.dart';
import 'vendedores_screen.dart';

class ReporteScreen extends StatefulWidget {
  const ReporteScreen({
    this.onCerrarSesion,
    this.onCambiarTema,
    this.modoOscuro = false,
    super.key,
  });

  final VoidCallback? onCerrarSesion;
  final VoidCallback? onCambiarTema;
  final bool modoOscuro;

  @override
  State<ReporteScreen> createState() => _ReporteScreenState();
}

class _ReporteScreenState extends State<ReporteScreen> {
  static const _opcionAnulada = 'ANULADA';
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
  double _zoom = .85;
  bool _vistaGeneral = false;
  bool _vistaCobrosMensuales = false;
  bool _vistaEstadisticas = false;
  bool _vistaVendedores = false;
  bool _vistaClientes = false;
  int _seccionMovil = 0;
  final _busquedaController = TextEditingController();
  StreamSubscription<List<Map<String, dynamic>>>? _filasSubscription;
  Timer? _busquedaFacturaTimer;
  int _versionBusqueda = 0;
  final Set<int> _filasExpandidas = {};
  bool _actualizando = false;
  int _versionCobrosMensuales = 0;

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

  Future<void> _abrirRecordatorios() => Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const PaymentRemindersScreen()),
      );

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
    try {
      final datos = await _supabaseReportes.obtenerReportesMensuales();

      await _reportes.cargarDesdeNube(datos);

      if (datos.isEmpty) {
        await _supabaseReportes.guardarReporteMensual(
          _reportes.activo.anio,
          _reportes.activo.mes,
        );
      }

      if (!mounted) return;

      _activarReporte(_reportes.activo, guardar: false);
    } catch (error) {
      _mostrarErrorNube('No se pudieron cargar los reportes: $error');
    }
  }

  Future<void> _actualizarDesdeSupabase() async {
    if (_actualizando) return;
    setState(() => _actualizando = true);
    try {
      final auth = Supabase.instance.client.auth;
      if (auth.currentSession == null) {
        throw const AuthException('La sesión ya no está activa.');
      }
      await auth.refreshSession();
      await _vendedores.cargar();
      await _cargarReportes();
      if (!mounted) return;
      if (_vistaCobrosMensuales) {
        setState(() => _versionCobrosMensuales++);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesión y datos actualizados correctamente.'),
        ),
      );
    } catch (error) {
      _mostrarErrorNube('No se pudo actualizar: $error');
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
  }

  void _activarReporte(ReporteMensual reporte, {bool guardar = true}) {
    _reportes.activo = reporte;
    _filas = reporte.filas;
    _normalizarFilas();
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
            final comentarios = dato['comentarios_abonos'];
            fila.abonos
              ..clear()
              ..addAll(
                List.generate(abonos.length, (indice) {
                  final comentario =
                      comentarios is List && indice < comentarios.length
                          ? comentarios[indice]?.toString() ?? ''
                          : '';
                  return Abono(
                    valor: (abonos[indice] as num?)?.toDouble() ?? 0,
                    comentario: comentario,
                  );
                }),
              );
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
        _normalizarFilas();
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

    if (_reportes.reportes.any(
      (reporte) => reporte.anio == anio && reporte.mes == mes,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ese reporte mensual ya existe. Selecciónalo en la lista.',
          ),
        ),
      );
      return;
    }

    try {
      // Primero se crea en Supabase.
      await _supabaseReportes.guardarReporteMensual(anio, mes);

      // Después se agrega a la aplicación.
      _reportes.crear(anio, mes);

      if (!mounted) return;

      _activarReporte(_reportes.activo);
    } catch (error) {
      _mostrarErrorNube('No se pudo crear el reporte: $error');
    }
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
    _filas = [FilaVenta(numero: 1)];
  }

  void _buscarFactura(int indice, String referencia) {
    _busquedaFacturaTimer?.cancel();
    final version = ++_versionBusqueda;
    _busquedaFacturaTimer = Timer(const Duration(milliseconds: 350), () {
      _buscarFacturaAhora(indice, referencia, version);
    });
  }

  void _cambiarReferencia(FilaVenta fila, String referencia) {
    setState(() {
      fila.referencia = referencia;
      _asegurarFilaVacia();
    });
    final indice = _filas.indexOf(fila);
    if (indice >= 0) _buscarFactura(indice, referencia);
  }

  Future<void> _buscarFacturaAhora(
    int indice,
    String referencia,
    int version,
  ) async {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Factura no encontrada')));
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
          backgroundColor: context.hg.warning,
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
    if (!fila.tieneDatos) return;
    try {
      await _supabaseReportes.guardarFila(fila, _reportes.activo.nombre);
    } catch (error) {
      _mostrarErrorNube('No se pudo guardar la fila ${fila.numero}: $error');
    }
  }

  void _mostrarErrorNube(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: context.hg.danger),
    );
  }

  void _normalizarFilas() {
    final filasConDatos = _filas.where((fila) => fila.tieneDatos).toList();
    for (var indice = 0; indice < filasConDatos.length; indice++) {
      filasConDatos[indice].numero = indice + 1;
    }
    _filas = [...filasConDatos, FilaVenta(numero: filasConDatos.length + 1)];
    _reportes.activo.filas = _filas;
  }

  void _asegurarFilaVacia() {
    _normalizarFilas();
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
            onPressed: () => Navigator.pop(context, (
              double.tryParse(montoController.text.replaceAll(',', '.')) ?? 0,
              comentarioController.text.trim(),
            )),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    montoController.dispose();
    comentarioController.dispose();
    if (!mounted) return;
    if (resultado != null) {
      final totalPropuesto = fila.totalAbonos - abono.valor + resultado.$1;
      if (resultado.$1 < 0 || totalPropuesto > fila.venta + 0.005) {
        if (nuevo) setState(() => fila.abonos.removeAt(indice));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.hg.warning,
            content: Text(
              'El total de abonos (\$${totalPropuesto.toStringAsFixed(2)}) '
              'supera el valor de la factura (\$${fila.venta.toStringAsFixed(2)}).',
            ),
          ),
        );
        return;
      }
    }
    setState(() {
      if (resultado == null) {
        if (nuevo) fila.abonos.removeAt(indice);
      } else {
        abono.valor = resultado.$1;
        abono.comentario = resultado.$2;
        _asegurarFilaVacia();
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

  void _gestionarVendedores() {
    setState(() {
      _vistaVendedores = true;
      _vistaCobrosMensuales = false;
      _vistaEstadisticas = false;
      _vistaGeneral = false;
      _seccionMovil = 3;
    });
  }

  // Conservado temporalmente como referencia de la interfaz anterior.
  // ignore: unused_element
  Future<void> _gestionarVendedoresAnterior() async {
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
                Row(
                  children: [
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Escoja el rango del reporte'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: desde,
                        decoration: const InputDecoration(
                          labelText: 'Desde',
                          border: OutlineInputBorder(),
                        ),
                        items: _reportes.reportes
                            .map(
                              (r) => DropdownMenuItem(
                                value: r.id,
                                child: Text(r.nombre),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => actualizar(() => desde = v ?? desde),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: hasta,
                        decoration: const InputDecoration(
                          labelText: 'Hasta',
                          border: OutlineInputBorder(),
                        ),
                        items: _reportes.reportes
                            .map(
                              (r) => DropdownMenuItem(
                                value: r.id,
                                child: Text(r.nombre),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => actualizar(() => hasta = v ?? hasta),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  initialValue: vendedor,
                  decoration: const InputDecoration(
                    labelText: 'Contenido',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todos los vendedores'),
                    ),
                    const DropdownMenuItem<String?>(
                      value: _opcionAnulada,
                      child: Text(_opcionAnulada),
                    ),
                    ..._vendedores.vendedores.map(
                      (v) => DropdownMenuItem<String?>(
                        value: v.etiqueta,
                        child: Text(v.etiqueta),
                      ),
                    ),
                  ],
                  onChanged: (v) => actualizar(() => vendedor = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
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
            content: Text(
              'El mes inicial no puede ser posterior al mes final.',
            ),
          ),
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
          content: Text('No hay datos para generar este reporte.'),
        ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF guardado en: $ruta')));
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
                    const DropdownMenuItem(
                      value: _opcionAnulada,
                      child: Text(_opcionAnulada),
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
              onPressed: () => Navigator.pop(context, (
                texto: '',
                vendedor: '',
                estado: 'todos',
              )),
              child: const Text('Limpiar filtros'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                texto: controller.text.trim(),
                vendedor: vendedor,
                estado: estado,
              )),
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
    final reporteEliminar = _reportes.activo;
    final nombre = reporteEliminar.nombre;
    final anio = reporteEliminar.anio;
    final mes = reporteEliminar.mes;

    final confirmacionController = TextEditingController();

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, actualizar) => AlertDialog(
          title: const Text('Eliminar reporte'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Esta acción eliminará completamente el reporte de $nombre y todos sus datos guardados.',
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Para confirmar, escribe “$nombre”:'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmacionController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: nombre,
                    prefixIcon: const Icon(Icons.warning_amber_rounded),
                  ),
                  onChanged: (_) => actualizar(() {}),
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
              onPressed: confirmacionController.text.trim() == nombre
                  ? () => Navigator.pop(context, true)
                  : null,
              style: FilledButton.styleFrom(backgroundColor: context.hg.danger),
              child: const Text('Eliminar definitivamente'),
            ),
          ],
        ),
      ),
    );

    confirmacionController.dispose();

    if (confirmado != true || !mounted) return;

    try {
      final eraUnico = _reportes.reportes.length == 1;

      // Elimina todas las filas del mes.
      await _supabaseReportes.eliminarFilasReporte(nombre);

      // Elimina también el mes de la lista de reportes.
      await _supabaseReportes.eliminarReporteMensual(anio, mes);

      // Actualiza la memoria local.
      _reportes.eliminarActivo();

      // ReportesStore crea automáticamente un nuevo mes
      // si acabamos de eliminar el único existente.
      if (eraUnico) {
        await _supabaseReportes.guardarReporteMensual(
          _reportes.activo.anio,
          _reportes.activo.mes,
        );
      }

      _filtro = '';
      _filtroVendedor = '';
      _filtroEstado = 'todos';

      if (!mounted) return;

      _activarReporte(_reportes.activo);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se eliminó el reporte de $nombre.')),
      );
    } catch (error) {
      _mostrarErrorNube('No se pudo eliminar el reporte: $error');
    }
  }

  Future<void> _eliminarReporteCliente() async {
    final candidatas = _filas.where((fila) => fila.tieneDatos).toList();
    if (candidatas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay reportes de clientes para eliminar.'),
        ),
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
                  .map(
                    (fila) => DropdownMenuItem(
                      value: fila.numero,
                      child: Text(
                        '${fila.cliente.isEmpty ? "Sin nombre" : fila.cliente} · Factura ${fila.numeroFactura.isEmpty ? fila.referencia : fila.numeroFactura}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
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
            style: FilledButton.styleFrom(backgroundColor: context.hg.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      await _supabaseReportes.eliminarFacturaMaestra(
        seleccionada.numeroFactura,
      );
      if (!mounted) return;
      _facturas.eliminar(seleccionada.numeroFactura);
      final indice = _filas.indexOf(seleccionada);
      setState(() {
        _filas[indice] = FilaVenta(numero: seleccionada.numero);
        _normalizarFilas();
      });
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
      return _filtrosColumnas.entries.every(
        (filtro) => _valorTexto(
          item.value,
          filtro.key,
        ).toLowerCase().contains(filtro.value.toLowerCase()),
      );
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
    final partes = RegExp(
      r'^(\d{1,4})[-/](\d{1,2})[-/](\d{1,4})',
    ).firstMatch(fecha.trim());
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
    if (_esReleaseMovil) return _vistaMovil();

    return Scaffold(
      body: Focus(
        focusNode: _focusZoom,
        autofocus: true,
        onKeyEvent: _atajoZoom,
        child: Listener(
          onPointerSignal: _ruedaZoom,
          child: Column(
            children: [
              _barraSuperior(),
              Expanded(
                child: _vistaVendedores
                    ? VendedoresContent(store: _vendedores)
                    : _vistaEstadisticas
                        ? const EstadisticasScreen()
                        : _vistaCobrosMensuales
                            ? CobrosMensualesView(
                                key: ValueKey(_versionCobrosMensuales),
                              )
                            : Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(28, 22, 28, 28),
                                child: Column(
                                  children: [
                                    _encabezadoPagina(),
                                    const SizedBox(height: 18),
                                    _tarjetasResumen(),
                                    const SizedBox(height: 18),
                                    _barraRedisenada(),
                                    const SizedBox(height: 14),
                                    Expanded(child: _tarjetaTabla()),
                                  ],
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _esReleaseMovil =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

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
              tooltip: 'Recordatorios de pago',
              onPressed: _abrirRecordatorios,
              icon: const Icon(Icons.notifications_active_outlined),
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
                _vistaClientes
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
              _seccionMovil = indice;
              _vistaCobrosMensuales = indice == 2;
              _vistaVendedores = indice == 3;
              _vistaClientes = indice == 4;
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
              icon: Icon(Icons.people_outline),
              label: 'Vendedores',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              label: 'Clientes',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              label: 'Estadísticas',
            ),
          ],
        ),
        body: _vistaVendedores
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
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              slivers: [
                                SliverPadding(
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 16, 14, 8),
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
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${_vistaGeneral ? _filasGenerales.length : _filasVisibles.length} registros',
                                            style: TextStyle(
                                              color: context.hg.mutedText,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_descripcionFiltro.isNotEmpty) ...[
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
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  context.hg.danger,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.all(13),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18),
                                            label:
                                                const Text('Eliminar reporte'),
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
                  onPressed: _nuevoReporte,
                  style: _estiloAccionMovil,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('Nuevo mes'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _abrirCargaFacturas,
                  style: _estiloAccionMovil,
                  icon: const Icon(Icons.upload_file, size: 17),
                  label: Text('Subir facturas (${_facturas.cantidad})'),
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
            value: _opcionAnulada,
            child: Text(_opcionAnulada),
          ),
          ..._vendedores.vendedores.map(
            (v) => DropdownMenuItem(value: v.etiqueta, child: Text(v.etiqueta)),
          ),
        ],
        onChanged: (v) => setState(() => _filtroVendedor = v ?? ''),
      );

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

  Widget _tarjetaFilaMovil(FilaVenta fila) {
    final expandida = _filasExpandidas.contains(fila.numero);
    return Container(
      decoration: BoxDecoration(
        color: context.hg.panel,
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
                        '\$${fila.saldo.toStringAsFixed(2)}',
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
                          '\$${fila.venta.toStringAsFixed(2)}',
                        ),
                        _datoMovil(
                          'Tot. abono',
                          '\$${fila.totalAbonos.toStringAsFixed(2)}',
                          color: context.hg.positive,
                        ),
                        _datoMovil(
                          'Saldo',
                          '\$${fila.saldo.toStringAsFixed(2)}',
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

  Widget _campoEditableMovil(
    String etiqueta,
    String valor,
    String sugerencia,
    ValueChanged<String> asignar,
    FilaVenta fila,
  ) =>
      Column(
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
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
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
            const Spacer(),
            _pestana(
              'Reporte de ventas',
              !_vistaGeneral &&
                  !_vistaCobrosMensuales &&
                  !_vistaEstadisticas &&
                  !_vistaVendedores,
              () => setState(() {
                _vistaGeneral = false;
                _vistaCobrosMensuales = false;
                _vistaEstadisticas = false;
                _vistaVendedores = false;
              }),
            ),
            _pestana(
              'Reporte general',
              _vistaGeneral &&
                  !_vistaCobrosMensuales &&
                  !_vistaEstadisticas &&
                  !_vistaVendedores,
              () => setState(() {
                _vistaGeneral = true;
                _vistaCobrosMensuales = false;
                _vistaEstadisticas = false;
                _vistaVendedores = false;
              }),
            ),
            _pestana(
              'Reporte de Cobros Mensuales',
              _vistaCobrosMensuales,
              () => setState(() {
                _vistaCobrosMensuales = true;
                _vistaEstadisticas = false;
                _vistaVendedores = false;
              }),
            ),
            _pestana('Vendedores', _vistaVendedores, _gestionarVendedores),
            _pestana(
              'Estadísticas',
              _vistaEstadisticas,
              () => setState(() {
                _vistaEstadisticas = true;
                _vistaCobrosMensuales = false;
                _vistaVendedores = false;
              }),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Recordatorios de pago',
              onPressed: _abrirRecordatorios,
              icon: const Icon(
                Icons.notifications_active_outlined,
                color: Colors.white70,
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
            _botonBarra(Icons.add, 'Nuevo mes', _nuevoReporte),
            const SizedBox(width: 8),
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
            _botonZoom(),
          ],
        ),
      );

  Future<void> _abrirCargaFacturas() async {
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
  }

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
              value: _opcionAnulada,
              child: Text(_opcionAnulada),
            ),
            ..._vendedores.vendedores.map(
              (v) =>
                  DropdownMenuItem(value: v.etiqueta, child: Text(v.etiqueta)),
            ),
          ],
          onChanged: (v) => setState(() => _filtroVendedor = v ?? ''),
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
  // ignore: unused_element
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

  // ignore: unused_element
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
                    value: _opcionAnulada,
                    child: Text(_opcionAnulada),
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

  Widget _tabla() => Padding(
        padding: EdgeInsets.zero,
        child: Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  DataTable(
                    horizontalMargin: 7 * _escalaReporte,
                    columnSpacing: 13 * _escalaReporte,
                    dataRowMinHeight: 38 * _escalaReporte,
                    dataRowMaxHeight: 58 * _escalaReporte,
                    headingRowHeight: 46 * _escalaReporte,
                    headingRowColor:
                        WidgetStatePropertyAll(context.hg.tableHeader),
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
                      DataColumn(
                          label: _encabezado('NOMBRE COMERCIAL', 'nombre')),
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

  Widget _tablaGeneral() => Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(context.hg.tableHeader),
              headingTextStyle: TextStyle(
                color: context.hg.mutedText,
                fontWeight: FontWeight.w600,
              ),
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
                  .map(
                    (fila) => DataRow(
                      color: fila.pagada
                          ? WidgetStatePropertyAll(
                              context.hg.positive.withValues(alpha: .12),
                            )
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
                        DataCell(
                          Text(
                            '\$${fila.saldo.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      );

  DataRow _crearFila(int indice, FilaVenta fila) => DataRow(
        key: ValueKey(fila.numero),
        color: fila.pagada
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
          DataCell(Text('\$${fila.venta.toStringAsFixed(2)}')),
          DataCell(_botonAbono(fila, 0)),
          DataCell(_botonAbono(fila, 1)),
          DataCell(_abonosAdicionales(fila)),
          DataCell(Text('\$${fila.totalAbonos.toStringAsFixed(2)}')),
          DataCell(
            Text(
              '\$${fila.saldo.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );

  Widget _selectorVendedor(FilaVenta fila) => SizedBox(
        width: 82 * _escalaReporte,
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
              value: _opcionAnulada,
              child: Text(_opcionAnulada),
            ),
          ]).toList(),
          selectedItemBuilder: (_) => _vendedores.vendedores
              .map<Widget>(
            (item) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                item.codigo.isEmpty ? item.nombre : item.codigo,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
              .followedBy(const [
            Align(alignment: Alignment.centerLeft, child: Text(_opcionAnulada)),
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

  String _refSinCeros(String valor) {
    final limpio = valor.trim();
    if (limpio.isEmpty) return '';

    final numero = int.tryParse(limpio);
    return numero?.toString() ?? limpio;
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

  // ignore: unused_element
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
}
