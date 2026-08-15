import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fila_venta.dart';
import '../services/facturas_store.dart';
import '../services/optimistic_persistence.dart';
import '../services/reporte_exporter.dart';
import '../services/reportes_store.dart';
import '../services/supabase_reportes_service.dart';
import '../services/vendedores_store.dart';
import '../theme/hg_theme.dart';
import 'carga_facturas_screen.dart';
import 'cobros_mensuales_view.dart';
import 'clientes_screen.dart';
import 'estadisticas_screen.dart';
import 'payment_calendar/payment_calendar_screen.dart';
import 'vendedores_screen.dart';

part 'reporte/reporte_screen_view.dart';

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
  bool _vistaCalendario = false;
  bool _vistaCargaFacturas = false;
  int _seccionMovil = 0;
  final _busquedaController = TextEditingController();
  StreamSubscription<List<Map<String, dynamic>>>? _filasSubscription;
  Timer? _busquedaFacturaTimer;
  int _versionBusqueda = 0;
  final Set<int> _filasExpandidas = {};
  bool _actualizando = false;
  int _versionCobrosMensuales = 0;
  List<FilaVenta> _filasConsolidadas = const [];

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

  void _abrirRecordatorios() => setState(() {
        _vistaCalendario = true;
        _vistaCargaFacturas = false;
        _vistaGeneral = false;
        _vistaCobrosMensuales = false;
        _vistaEstadisticas = false;
        _vistaVendedores = false;
        _vistaClientes = false;
      });

  void _mostrarReporteVentas() => setState(() {
        _vistaCalendario = false;
        _vistaCargaFacturas = false;
        _vistaGeneral = false;
        _vistaCobrosMensuales = false;
        _vistaEstadisticas = false;
        _vistaVendedores = false;
        _vistaClientes = false;
        _seccionMovil = 0;
      });

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

      final consolidadas = await _supabaseReportes.obtenerFilasConsolidadas();

      if (datos.isEmpty) {
        await _supabaseReportes.guardarReporteMensual(
          _reportes.activo.anio,
          _reportes.activo.mes,
        );
      }

      if (!mounted) return;

      _filasConsolidadas = consolidadas;

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
          final referenciaNube = dato['ref_fact']?.toString().trim() ?? '';
          fila
            ..vendedor = dato['vendedor']?.toString() ?? ''
            ..esmalte = (dato['esmaltes'] as num?)?.toInt() ?? 0;
          // Legacy rows can have an empty ref_fact even though the locally
          // imported report still has the reference (most visibly, row 1).
          // Do not erase that valid value while synchronizing.
          if (referenciaNube.isNotEmpty) fila.referencia = referenciaNube;
          final abonos = dato['abonos'];
          if (abonos is List) {
            final comentarios = dato['comentarios_abonos'];
            final numerosRecibo = dato['numeros_recibo'];
            fila.abonos
              ..clear()
              ..addAll(
                List.generate(abonos.length, (indice) {
                  final comentario =
                      comentarios is List && indice < comentarios.length
                          ? comentarios[indice]?.toString() ?? ''
                          : '';
                  final recibo = numerosRecibo is List &&
                          indice < numerosRecibo.length &&
                          numerosRecibo[indice] != null
                      ? int.tryParse(numerosRecibo[indice].toString())
                      : null;
                  return Abono(
                    valor: (abonos[indice] as num?)?.toDouble() ?? 0,
                    numeroRecibo: recibo,
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
    final filaAnterior = FilaVenta.fromJson(fila.toJson());
    setState(() {
      fila.referencia = valor;
      fila.cliente = facturaEncontrada.cliente;
      fila.nombreComercial = facturaEncontrada.nombreComercial;
      fila.fecha = facturaEncontrada.fecha;
      fila.numeroFactura = facturaEncontrada.secuencial;
      fila.venta = facturaEncontrada.total;
      _asegurarFilaVacia();
    });
    await _guardarProgreso();
    final guardada = await persistirConReversion(
      persistir: () =>
          _supabaseReportes.guardarFila(fila, _reportes.activo.nombre),
      revertir: () async {
        if (!mounted) return;
        setState(() {
          final indiceActual = _filas.indexOf(fila);
          if (indiceActual >= 0) _filas[indiceActual] = filaAnterior;
          _normalizarFilas();
        });
        await _guardarProgreso();
      },
    );
    if (!guardada && mounted) {
      _mostrarErrorNube(
        'No fue posible guardar la factura en Supabase. '
        'La factura no fue registrada.',
      );
    }
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

  Future<bool> _guardarFilaNube(FilaVenta fila) async {
    if (!fila.tieneDatos) return true;
    try {
      await _supabaseReportes.guardarFila(fila, _reportes.activo.nombre);
      return true;
    } catch (error) {
      _mostrarErrorNube('No se pudo guardar la fila ${fila.numero}: $error');
      return false;
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
    Abono? borrador,
  }) async {
    final abono = borrador ?? (nuevo ? Abono() : fila.abonos[indice]);
    final montoController = TextEditingController(
      text: abono.valor == 0 ? '' : abono.valor.toStringAsFixed(2),
    );
    final reciboController = TextEditingController(
      text: abono.numeroRecibo?.toString() ?? '',
    );
    final comentarioController = TextEditingController(text: abono.comentario);
    final formKey = GlobalKey<FormState>();
    final resultado = await showDialog<(double, int?, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Abono ${indice + 1}'),
        content: SizedBox(
          width: 360,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
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
                  validator: (valor) => validarValorAbono(valor ?? ''),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: reciboController,
                  keyboardType: TextInputType.number,
                  validator: (valor) => validarNumeroRecibo(valor ?? ''),
                  decoration: const InputDecoration(
                    labelText: 'Número de recibo (opcional)',
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(context, (
                double.tryParse(montoController.text.replaceAll(',', '.')) ?? 0,
                reciboController.text.trim().isEmpty
                    ? null
                    : int.parse(reciboController.text.trim()),
                comentarioController.text.trim(),
              ));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    montoController.dispose();
    reciboController.dispose();
    comentarioController.dispose();
    if (!mounted) return;
    if (resultado != null) {
      final totalPropuesto = fila.totalAbonos - abono.valor + resultado.$1;
      if (totalPropuesto > fila.venta + 0.005) {
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
    if (resultado == null) return;

    // Persistimos una copia: totales y saldo visibles no cambian hasta que la
    // RPC confirme. Ante cualquier error, el estado local permanece intacto.
    final propuesta = FilaVenta.fromJson(fila.toJson());
    final abonoPropuesto = Abono(
      valor: resultado.$1,
      numeroRecibo: resultado.$2,
      comentario: resultado.$3,
    );
    if (nuevo) {
      propuesta.abonos.add(abonoPropuesto);
    } else {
      propuesta.abonos[indice] = abonoPropuesto;
    }
    late final FilaVenta confirmada;
    try {
      confirmada = await _supabaseReportes.guardarFila(
        propuesta,
        _reportes.activo.nombre,
      );
    } catch (error) {
      if (!mounted) return;
      _mostrarErrorNube(
        'No fue posible guardar el abono. Inténtalo nuevamente.',
      );
      await _editarAbono(
        fila,
        indice,
        nuevo: nuevo,
        borrador: abonoPropuesto,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      fila.abonos
        ..clear()
        ..addAll(confirmada.abonos);
      _asegurarFilaVacia();
    });
    await _guardarProgreso();
  }

  Future<void> _agregarAbono(FilaVenta fila) async {
    await _editarAbono(fila, fila.abonos.length, nuevo: true);
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
                      'Número de recibo: '
                      '${fila.abonos[indice].numeroRecibo?.toString() ?? 'Sin número de recibo (registro histórico)'}\n'
                      'Comentario: ${fila.abonos[indice].comentario.isEmpty ? 'Sin comentario' : fila.abonos[indice].comentario}',
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
      _vistaCalendario = false;
      _vistaCargaFacturas = false;
      _vistaVendedores = true;
      _vistaClientes = false;
      _vistaCobrosMensuales = false;
      _vistaEstadisticas = false;
      _vistaGeneral = false;
      _seccionMovil = 4;
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
      _filasParaTotales.where((fila) => !fila.anulada).fold(
            0,
            (suma, fila) => suma + fila.esmalte,
          );
  double get _totalVentas =>
      _filasParaTotales.where((fila) => !fila.anulada).fold(
            0,
            (suma, fila) => suma + fila.venta,
          );
  double get _totalCobros =>
      _filasParaTotales.where((fila) => !fila.anulada).fold(
            0,
            (suma, fila) => suma + fila.totalAbonos,
          );
  double get _totalPorCobrar =>
      _filasParaTotales.where((fila) => !fila.anulada).fold(
            0,
            (suma, fila) => suma + fila.saldo,
          );

  List<FilaVenta> get _filasGenerales {
    final texto = _filtro.toLowerCase();
    final resultado = _filasConsolidadas.where((fila) {
      if (!fila.tieneDatos) return false;
      final coincide = texto.isEmpty ||
          fila.referencia.toLowerCase().contains(texto) ||
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
    final columna = _ordenColumna;
    if (columna != null) {
      resultado.sort((a, b) {
        final comparacion = _valorOrden(a, columna).toString().compareTo(
              _valorOrden(b, columna).toString(),
            );
        return _ordenAscendente ? comparacion : -comparacion;
      });
    }
    return resultado;
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
                child: _vistaCalendario
                    ? const PaymentCalendarView()
                    : _vistaCargaFacturas
                        ? CargaFacturasView(
                            key: ValueKey(_reportes.activo.id),
                            mes: _reportes.activo.mes,
                            anio: _reportes.activo.anio,
                            onVolver: _mostrarReporteVentas,
                            onFacturasGuardadas: _guardarProgreso,
                          )
                        : _vistaClientes
                            ? const ClientesScreen()
                            : _vistaVendedores
                                ? VendedoresContent(store: _vendedores)
                                : _vistaEstadisticas
                                    ? const EstadisticasScreen()
                                    : _vistaCobrosMensuales
                                        ? CobrosMensualesView(
                                            key: ValueKey(
                                                _versionCobrosMensuales),
                                          )
                                        : Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                28, 22, 28, 28),
                                            child: Column(
                                              children: [
                                                _encabezadoPagina(),
                                                const SizedBox(height: 18),
                                                _tarjetasResumen(),
                                                const SizedBox(height: 18),
                                                _barraRedisenada(),
                                                const SizedBox(height: 14),
                                                Expanded(
                                                    child: _tarjetaTabla()),
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

  // ignore: unused_element
}
