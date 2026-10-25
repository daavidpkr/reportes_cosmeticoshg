import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fila_venta.dart';
import '../models/billing_customer.dart';
import '../models/customer_history.dart';
import '../models/payment_calendar_entry.dart';
import '../services/customer_terms_repository.dart';
import '../services/facturas_store.dart';
import '../services/invoice_batch_importer.dart';
import '../services/payment_calendar_refresh.dart';
import '../services/payment_calendar_repository.dart';
import '../services/report_filter_preferences.dart';
import '../services/reporte_exporter.dart';
import '../services/reportes_store.dart';
import '../services/supabase_reportes_service.dart';
import '../services/vendedores_store.dart';
import '../theme/hg_theme.dart';
import '../widgets/payment_editor_dialog.dart';
import 'carga_facturas_screen.dart';
import 'cobros_mensuales_view.dart';
import 'catalogs/catalogs_screen.dart';
import 'clientes_screen.dart';
import 'customer_history_screen.dart';
import 'estadisticas_screen.dart';
import 'general_search_screen.dart';
import 'invoice_detail_dialog.dart';
import 'payment_calendar/payment_calendar_screen.dart';
import 'payment_calendar/dialogs/reschedule_reminder_dialog.dart';
import 'reporte/report_invoice_table.dart';
import 'payment_reminders_screen.dart';
import 'updates_screen.dart';
import 'reporte/report_responsive_layout.dart';
import 'vendedores_screen.dart';

export 'reporte/report_responsive_layout.dart';

part 'reporte/reporte_screen_view.dart';

const reportSummaryLabels = <String>[
  'Total de ventas histórico',
  'Total de cobrar histórico',
  'Total de esmaltes histórico',
  'Total de ventas mensuales',
  'Total de cobros mensuales',
  'Cartera mensual por cobrar',
];

enum ReportSummaryGroup { historical, monthly }

({Color foreground, Color background}) reportSummaryColors(
  HgThemeColors colors,
  ReportSummaryGroup group,
) =>
    switch (group) {
      ReportSummaryGroup.historical => (
          foreground: colors.warning,
          background: colors.warningContainer,
        ),
      ReportSummaryGroup.monthly => (
          foreground: colors.positive,
          background: colors.positiveContainer,
        ),
    };

const mobileReportNavigationLabels = <String>[
  'Ventas',
  'Búsqueda general',
  'Clientes',
  'Calendario'
];
const mobileReportNavigationDestinations = <NavigationDestination>[
  NavigationDestination(
    icon: Icon(Icons.receipt_long_outlined),
    label: 'Ventas',
  ),
  NavigationDestination(
    icon: Icon(Icons.manage_search_outlined),
    label: 'Búsqueda general',
  ),
  NavigationDestination(
    icon: Icon(Icons.groups_outlined),
    label: 'Clientes',
  ),
  NavigationDestination(
    icon: Icon(Icons.calendar_month_outlined),
    label: 'Calendario',
  ),
];
const mobileReportMenuSectionLabels = <String>[
  'Cobros mensuales',
  'Catálogos',
];

const logoReportMenuLabels = <String>[
  'Vendedores',
  'Estadísticas',
];

enum ReportDestination {
  sales,
  monthlyCollections,
  clients,
  globalSearch,
  sellers,
  statistics,
  calendar,
  invoiceImport,
  catalogs,
}

int? mobileNavigationIndex(ReportDestination destination) =>
    switch (destination) {
      ReportDestination.sales => 0,
      ReportDestination.globalSearch => 1,
      ReportDestination.clients => 2,
      ReportDestination.calendar => 3,
      _ => null,
    };

ReportDestination destinationForMobileIndex(int index) => switch (index) {
      1 => ReportDestination.globalSearch,
      2 => ReportDestination.clients,
      3 => ReportDestination.calendar,
      _ => ReportDestination.sales,
    };

bool isPrimaryReportDestination(ReportDestination destination) =>
    mobileNavigationIndex(destination) != null;

class ReportLogoMenu extends StatelessWidget {
  const ReportLogoMenu({
    required this.destination,
    required this.onSelected,
    this.compact = false,
    super.key,
  });

  final ReportDestination destination;
  final ValueChanged<ReportDestination> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Menú de Cosméticos HG',
      hint: 'Abre las opciones Vendedores y Estadísticas',
      child: PopupMenuButton<ReportDestination>(
        key: const Key('report-logo-menu'),
        tooltip: 'Abrir menú de Cosméticos HG',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 4),
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
        onSelected: onSelected,
        itemBuilder: (_) => [
          CheckedPopupMenuItem(
            value: ReportDestination.sellers,
            checked: destination == ReportDestination.sellers,
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.people_outline),
              title: Text('Vendedores'),
            ),
          ),
          CheckedPopupMenuItem(
            value: ReportDestination.statistics,
            checked: destination == ReportDestination.statistics,
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.insights_outlined),
              title: Text('Estadísticas'),
            ),
          ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(
                  'web/icons/Icon-192.png',
                  width: compact ? 32 : 34,
                  height: compact ? 32 : 34,
                  fit: BoxFit.cover,
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 10),
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cosméticos HG',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
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
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReporteScreen extends StatefulWidget {
  const ReporteScreen({
    this.onCerrarSesion,
    this.onCambiarTema,
    this.modoOscuro = false,
    this.initialCalendarDate,
    this.calendarRequestId = 0,
    super.key,
  });

  final VoidCallback? onCerrarSesion;
  final VoidCallback? onCambiarTema;
  final bool modoOscuro;
  final DateTime? initialCalendarDate;
  final int calendarRequestId;

  @override
  State<ReporteScreen> createState() => _ReporteScreenState();
}

class _ReporteScreenState extends State<ReporteScreen>
    with WidgetsBindingObserver {
  static const _opcionAnul = 'ANUL';
  static const _opcionAnulada = 'ANULADA';
  final _facturas = FacturasStore.instance;
  final _exporter = ReporteExporter();
  final _vendedores = VendedoresStore();
  final _reportes = ReportesStore();
  final _filterPreferences = ReportFilterPreferencesStore();
  final _supabaseReportes = SupabaseReportesService();
  PaymentCalendarRepository? _paymentCalendarRepository;
  CustomerTermsDataSource? _customerTermsRepository;
  PaymentCalendarRepository get _invoiceCustomerResolver =>
      _paymentCalendarRepository ??= PaymentCalendarRepository();
  CustomerTermsDataSource get _profileCustomerTerms =>
      _customerTermsRepository ??= CustomerTermsRepository();
  late List<FilaVenta> _filas;
  String _filtro = '';
  String _filtroVendedor = '';
  String _filtroEstado = 'todos';
  String _filtroPlazo = '';
  final Map<String, String> _filtrosColumnas = {};
  String? _ordenColumna;
  bool _ordenAscendente = true;
  ReportDestination _destination = ReportDestination.sales;
  final List<ReportDestination> _destinationHistory = [];
  int _handledCalendarRequestId = 0;
  final _busquedaController = TextEditingController();
  StreamSubscription<List<Map<String, dynamic>>>? _filasSubscription;
  int _realtimeGeneration = 0;
  bool _appEnPrimerPlano = true;
  bool _openingInvoiceDetail = false;
  bool _actualizando = false;
  final Set<String> _abonosGuardandose = {};
  int _versionCobrosMensuales = 0;
  ReportAggregates _historicalAggregates = const ReportAggregates.empty();
  String? _filterUserId;
  String? _filterOrganizationId;

  bool get _vistaCobrosMensuales =>
      _destination == ReportDestination.monthlyCollections;
  bool get _vistaEstadisticas => _destination == ReportDestination.statistics;
  bool get _vistaVendedores => _destination == ReportDestination.sellers;
  bool get _vistaClientes => _destination == ReportDestination.clients;
  bool get _vistaCalendario => _destination == ReportDestination.calendar;
  bool get _vistaCargaFacturas =>
      _destination == ReportDestination.invoiceImport;
  bool get _vistaBusquedaGeneral =>
      _destination == ReportDestination.globalSearch;
  bool get _vistaCatalogos => _destination == ReportDestination.catalogs;
  bool get _esAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _navigate(ReportDestination destination) {
    if (_destination == destination) return;
    setState(() {
      if (isPrimaryReportDestination(destination)) {
        _destinationHistory.clear();
      } else {
        final previousIndex = _destinationHistory.lastIndexOf(destination);
        if (previousIndex >= 0) {
          _destinationHistory.removeRange(
            previousIndex,
            _destinationHistory.length,
          );
        } else if (_destinationHistory.isEmpty ||
            _destinationHistory.last != _destination) {
          _destinationHistory.add(_destination);
        }
      }
      _destination = destination;
    });
  }

  void _goBack() {
    if (isPrimaryReportDestination(_destination)) return;
    setState(() {
      _destination = _destinationHistory.isEmpty
          ? ReportDestination.sales
          : _destinationHistory.removeLast();
    });
  }

  ReportResponsiveLayout get _reportLayout =>
      ReportResponsiveLayout.forWidth(MediaQuery.sizeOf(context).width);

  double get _escalaReporte => _reportLayout.tableScale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appEnPrimerPlano =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _crearFilas();
    _inicializar();
    _applyCalendarRequest();
  }

  @override
  void didUpdateWidget(covariant ReporteScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.calendarRequestId != widget.calendarRequestId) {
      setState(_applyCalendarRequest);
    }
  }

  void _applyCalendarRequest() {
    if (widget.initialCalendarDate == null ||
        widget.calendarRequestId == _handledCalendarRequestId) {
      return;
    }
    _handledCalendarRequestId = widget.calendarRequestId;
    _destinationHistory.clear();
    _destination = ReportDestination.calendar;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeGeneration++;
    _filasSubscription?.cancel();
    _busquedaController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final enPrimerPlano = state == AppLifecycleState.resumed;
    if (enPrimerPlano == _appEnPrimerPlano) return;
    _appEnPrimerPlano = enPrimerPlano;
    if (!enPrimerPlano) {
      _realtimeGeneration++;
      final subscription = _filasSubscription;
      _filasSubscription = null;
      if (subscription != null) unawaited(subscription.cancel());
      return;
    }
    unawaited(_recuperarYEscucharReporteActivo());
  }

  void _abrirRecordatorios() => _navigate(ReportDestination.calendar);

  void _mostrarReporteVentas() => _navigate(ReportDestination.sales);

  void _mostrarClientes() => _navigate(ReportDestination.clients);

  Future<void> _inicializar() async {
    await Future.wait([_cargarVendedores(), _cargarReportes()]);
    await _restaurarFiltros();
  }

  Future<void> _restaurarFiltros() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final organization =
          await Supabase.instance.client.rpc('current_organization_id');
      final organizationId = organization?.toString();
      if (userId == null || organizationId == null || organizationId.isEmpty) {
        return;
      }
      _filterUserId = userId;
      _filterOrganizationId = organizationId;
      final saved = await _filterPreferences.load(
        userId: userId,
        organizationId: organizationId,
      );
      if (!mounted || saved == null) return;
      final validSeller = saved.seller.isEmpty ||
          saved.seller == _opcionAnulada ||
          _vendedores.vendedores
              .any((seller) => seller.etiqueta == saved.seller);
      setState(() {
        _filtro = saved.query;
        _filtroVendedor = validSeller ? saved.seller : '';
        _filtroEstado = saved.status;
        _filtroPlazo = saved.paymentTerm;
        _filtrosColumnas
          ..clear()
          ..addAll(saved.columnFilters);
        _ordenColumna = saved.sortColumn;
        _ordenAscendente = saved.sortAscending;
        _busquedaController.text = _filtro;
      });
      if (!validSeller) unawaited(_guardarFiltros());
    } catch (_) {
      // La configuración local nunca debe impedir cargar los datos remotos.
    }
  }

  Future<void> _guardarFiltros() async {
    final userId = _filterUserId;
    final organizationId = _filterOrganizationId;
    if (userId == null || organizationId == null) return;
    await _filterPreferences.save(
      userId: userId,
      organizationId: organizationId,
      value: ReportFilterPreferences(
        query: _filtro,
        seller: _filtroVendedor,
        status: _filtroEstado,
        paymentTerm: _filtroPlazo,
        columnFilters: Map.unmodifiable(_filtrosColumnas),
        sortColumn: _ordenColumna,
        sortAscending: _ordenAscendente,
      ),
    );
  }

  void _actualizarFiltros(VoidCallback change) {
    setState(change);
    unawaited(_guardarFiltros());
  }

  Future<void> _limpiarFiltros() async {
    setState(() {
      _filtro = '';
      _filtroVendedor = '';
      _filtroEstado = 'todos';
      _filtroPlazo = '';
      _filtrosColumnas.clear();
      _ordenColumna = null;
      _ordenAscendente = true;
      _busquedaController.clear();
    });
    final userId = _filterUserId;
    final organizationId = _filterOrganizationId;
    if (userId != null && organizationId != null) {
      await _filterPreferences.clear(
        userId: userId,
        organizationId: organizationId,
      );
    }
  }

  Future<void> _cargarVendedores() async {
    await _vendedores.cargar();
    if (mounted) setState(() {});
  }

  Future<void> _cargarReportes() async {
    try {
      final resultados = await Future.wait([
        _supabaseReportes.obtenerReportesMensuales(),
        _supabaseReportes.obtenerAgregadosReportes(),
      ]);
      final datos = List<Map<String, dynamic>>.from(resultados[0] as List);

      await _reportes.cargarDesdeNube(datos);

      if (datos.isEmpty) {
        await _supabaseReportes.guardarReporteMensual(
          _reportes.activo.anio,
          _reportes.activo.mes,
        );
      }

      if (!mounted) return;

      _historicalAggregates = resultados[1] as ReportAggregates;

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

  Future<void> _actualizarConsumidoresDeAbonos() async {
    final aggregates = await _supabaseReportes.obtenerAgregadosReportes();
    if (!mounted) return;
    setState(() {
      _historicalAggregates = aggregates;
      _versionCobrosMensuales++;
    });
  }

  void _activarReporte(ReporteMensual reporte, {bool guardar = true}) {
    _reportes.activo = reporte;
    _filas = reporte.filas;
    _normalizarFilas();
    _facturas
      ..mesPermitido = reporte.mes
      ..anioPermitido = reporte.anio
      ..cargar(reporte.facturas);
    if (mounted) setState(() {});
    _escucharReporteActivo();
    if (guardar) _guardarProgreso();
  }

  void _escucharReporteActivo() {
    final reporte = _reportes.activo;
    unawaited(_crearSuscripcionRealtime(reporte));
  }

  Future<void> _recuperarYEscucharReporteActivo() async {
    final reporte = _reportes.activo;
    final generation = ++_realtimeGeneration;
    final anterior = _filasSubscription;
    _filasSubscription = null;
    if (anterior != null) await anterior.cancel();
    try {
      final datos = await _supabaseReportes.obtenerFilasReporte(reporte.nombre);
      if (!_realtimeVigente(generation, reporte)) return;
      _aplicarFilasRealtime(datos, reporte);
      await _crearSuscripcionRealtime(reporte, generation: generation);
    } catch (error) {
      if (_realtimeVigente(generation, reporte)) {
        _mostrarErrorRealtime(error);
      }
    }
  }

  Future<void> _crearSuscripcionRealtime(
    ReporteMensual reporte, {
    int? generation,
  }) async {
    final currentGeneration = generation ?? ++_realtimeGeneration;
    final anterior = _filasSubscription;
    _filasSubscription = null;
    if (anterior != null) await anterior.cancel();
    if (!_realtimeVigente(currentGeneration, reporte)) return;
    _filasSubscription = _supabaseReportes.observarFilas(reporte.nombre).listen(
      (datos) {
        if (!_realtimeVigente(currentGeneration, reporte)) return;
        _aplicarFilasRealtime(datos, reporte);
      },
      onError: (Object error) {
        if (!_realtimeVigente(currentGeneration, reporte)) return;
        _mostrarErrorRealtime(error);
      },
    );
  }

  bool _realtimeVigente(int generation, ReporteMensual reporte) =>
      mounted &&
      _appEnPrimerPlano &&
      generation == _realtimeGeneration &&
      _reportes.activo.id == reporte.id;

  void _aplicarFilasRealtime(
    List<Map<String, dynamic>> datos,
    ReporteMensual reporte,
  ) {
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
  }

  void _mostrarErrorRealtime(Object error) {
    if (!mounted || !_appEnPrimerPlano) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No se pudo sincronizar el reporte en tiempo real: $error',
        ),
        backgroundColor: context.hg.danger,
        action: SnackBarAction(
          label: 'Reintentar',
          textColor: Colors.white,
          onPressed: () => unawaited(_recuperarYEscucharReporteActivo()),
        ),
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

  Future<bool> _editarAbono(
    FilaVenta fila,
    int indice, {
    bool nuevo = false,
    Abono? borrador,
    String? mesReporte,
    bool pagoCompletoInicial = false,
  }) async {
    if (fila.anulada) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Una factura anulada no puede recibir abonos.'),
        ),
      );
      return false;
    }
    final abono = borrador ?? (nuevo ? Abono() : fila.abonos[indice]);
    final saldoInicial = fila.saldo + (nuevo ? 0 : abono.valor);
    final factura = fila.numeroFactura.trim().isEmpty
        ? fila.referencia
        : fila.numeroFactura;
    final resultado = await showPaymentEditorDialog(
      context: context,
      title: 'Abono ${indice + 1}',
      initialPayment: abono,
      availableBalance: saldoInicial,
      initialFullPayment: pagoCompletoInicial && nuevo,
      fullPaymentEnabled: !fila.pagada,
      allowDelete: !nuevo,
      invoiceLabel: factura,
      deleteSemanticLabel: 'Eliminar abono ${indice + 1}',
    );
    if (!mounted) return false;
    if (resultado?.action == PaymentEditorAction.delete) {
      await _eliminarAbono(
        fila,
        indice,
        abono,
        mesReporte: mesReporte,
      );
      return true;
    }
    final pagoResultado = resultado?.payment;
    if (pagoResultado != null) {
      final totalPropuesto =
          fila.totalAbonos - abono.valor + pagoResultado.valor;
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
        return false;
      }
    }
    if (pagoResultado == null) return false;

    // Persistimos una copia: totales y saldo visibles no cambian hasta que la
    // RPC confirme. Ante cualquier error, el estado local permanece intacto.
    final propuesta = FilaVenta.fromJson(fila.toJson());
    final abonoPropuesto = Abono(
      valor: pagoResultado.valor,
      numeroRecibo: pagoResultado.numeroRecibo,
      comentario: pagoResultado.comentario,
    );
    if (nuevo) {
      propuesta.abonos.add(abonoPropuesto);
    } else {
      propuesta.abonos[indice] = abonoPropuesto;
    }
    final reportName = mesReporte ?? _reportes.activo.nombre;
    final saveKey = '$reportName:${fila.numero}:$indice';
    if (!_abonosGuardandose.add(saveKey)) return false;
    late final FilaVenta confirmada;
    try {
      confirmada = await _supabaseReportes.guardarFila(
        propuesta,
        reportName,
      );
    } catch (error) {
      _abonosGuardandose.remove(saveKey);
      if (!mounted) return false;
      _mostrarErrorNube(
        'No fue posible guardar el abono. Inténtalo nuevamente.',
      );
      return _editarAbono(
        fila,
        indice,
        nuevo: nuevo,
        borrador: abonoPropuesto,
        mesReporte: mesReporte,
      );
    }
    _abonosGuardandose.remove(saveKey);
    if (!mounted) return false;
    setState(() {
      fila.abonos
        ..clear()
        ..addAll(confirmada.abonos);
      if (mesReporte == null) _asegurarFilaVacia();
    });
    if (mesReporte == null) {
      await _guardarProgreso();
      await _actualizarConsumidoresDeAbonos();
    } else {
      await _cargarReportes();
      if (mounted) setState(() => _versionCobrosMensuales++);
    }
    paymentCalendarRefresh.refresh();
    return true;
  }

  Future<void> _abrirDetalleFactura(
    FilaVenta fila, {
    String? mesReporte,
    bool desdePerfilCliente = false,
  }) async {
    if (_openingInvoiceDetail) return;
    _openingInvoiceDetail = true;
    DateTime? scheduledDate;
    try {
      scheduledDate =
          await _supabaseReportes.obtenerFechaCobro(fila.referencia);
    } catch (_) {}
    if (!mounted) {
      _openingInvoiceDetail = false;
      return;
    }
    try {
      await showInvoiceDetailDialog(
        context,
        invoice: fila,
        scheduledDate: scheduledDate,
        reportMonth: mesReporte ?? _reportes.activo.nombre,
        onPayment: () async {
          await _editarAbono(
            fila,
            fila.abonos.length,
            nuevo: true,
            mesReporte: mesReporte,
          );
        },
        onEditPayment: (index) async {
          await _editarAbono(
            fila,
            index,
            mesReporte: mesReporte,
          );
        },
        onPayInFull: () async {
          await _editarAbono(
            fila,
            fila.abonos.length,
            nuevo: true,
            mesReporte: mesReporte,
            pagoCompletoInicial: true,
          );
        },
        onReschedule: () => _reprogramarDesdeDetalle(fila),
        onViewCustomerProfile:
            desdePerfilCliente ? null : () => _openCustomerProfile(fila),
        onClosed: () async {
          if (mesReporte != null) await _cargarReportes();
          paymentCalendarRefresh.refresh();
          if (mounted) setState(() {});
        },
      );
    } finally {
      _openingInvoiceDetail = false;
    }
  }

  Future<void> _abrirDetalleDesdePerfil(
    CustomerHistoryInvoice invoice,
    BillingCustomer customer,
  ) async {
    List<GlobalInvoiceRow> matches;
    try {
      matches = await _supabaseReportes.buscarFilasGlobales(
        invoice.reference,
        offset: 0,
        limit: 50,
      );
    } catch (_) {
      if (mounted) {
        _mostrarErrorNube('No se pudo cargar el detalle de la factura.');
      }
      return;
    }
    if (!mounted) return;
    final exact = matches.where(
      (item) =>
          item.row.referencia.trim() == invoice.reference.trim() &&
          item.reportMonth == invoice.reportMonth,
    );
    final fallback = matches.where(
      (item) => item.row.referencia.trim() == invoice.reference.trim(),
    );
    final match = exact.firstOrNull ?? fallback.firstOrNull;
    if (match == null) {
      _mostrarErrorNube('No se encontró la fila original de esta factura.');
      return;
    }
    if (match.row.cliente.trim().isEmpty) {
      match.row.cliente = customer.name;
    }
    if (match.row.nombreComercial.trim().isEmpty) {
      match.row.nombreComercial = customer.commercialName;
    }
    await _abrirDetalleFactura(
      match.row,
      mesReporte: match.reportMonth,
      desdePerfilCliente: true,
    );
  }

  Future<bool> _openCustomerProfile(FilaVenta invoice) async {
    BillingCustomer? customer;
    try {
      customer = await _invoiceCustomerResolver
          .resolveCustomer(invoice.referencia.trim());
    } catch (_) {
      customer = null;
    }
    if (!mounted || customer == null) return false;
    await showDialog<void>(
      context: context,
      builder: (_) => CustomerHistoryScreen(
        customer: customer!,
        onToggleTheme: widget.onCambiarTema,
        onEditTerm: _editProfileCustomerTerm,
        onEditHours: (customer, value) async {
          final updated = await _profileCustomerTerms.saveBusinessHours(
            customer.id,
            value,
          );
          paymentCalendarRefresh.refresh();
          return updated;
        },
        onSchedule: _scheduleProfileCustomer,
        onDelete: _deleteProfileCustomer,
        onOpenInvoiceDetail: _abrirDetalleDesdePerfil,
      ),
    );
    if (!mounted) return true;
    paymentCalendarRefresh.refresh();
    return true;
  }

  Future<int?> _editProfileCustomerTerm(BillingCustomer customer) async {
    final input = TextEditingController(
      text: customer.paymentTermDays?.toString() ?? '',
    );
    final days = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Plazo habitual de pago'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Días'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(input.text.trim()),
            ),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    input.dispose();
    if (days == null || days < 0 || !mounted) return null;
    final impacted = await _profileCustomerTerms.previewImpact(
      customer.id,
      days,
    );
    if (!mounted) return null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar plazo'),
        content: Text(
          impacted == 0
              ? 'Se guardará el plazo habitual del cliente.'
              : 'Se actualizarán $impacted facturas existentes con el nuevo plazo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
    await _profileCustomerTerms.savePaymentTerm(
      customer.id,
      days,
      applyExisting: true,
    );
    paymentCalendarRefresh.refresh();
    return days;
  }

  Future<void> _scheduleProfileCustomer(BillingCustomer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Programar facturas pendientes'),
        content: Text(
          'Se programarán las facturas elegibles de ${customer.name} sin modificar recordatorios existentes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Programar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _profileCustomerTerms.schedulePending(customer);
    paymentCalendarRefresh.refresh();
  }

  Future<bool> _deleteProfileCustomer(BillingCustomer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: const Text(
          'Se quitará al cliente del apartado Clientes. Sus facturas, abonos y recordatorios se conservarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar cliente'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await _profileCustomerTerms.deleteCustomer(customer);
    paymentCalendarRefresh.refresh();
    return true;
  }

  Future<void> _reprogramarDesdeDetalle(FilaVenta fila) async {
    final repository = PaymentCalendarRepository();
    try {
      final matches =
          await repository.searchSchedulableInvoices(fila.referencia);
      SchedulableInvoice? invoice;
      for (final item in matches) {
        if (item.facturaId == fila.referencia.trim()) {
          invoice = item;
          break;
        }
      }
      if (invoice == null) {
        _mostrarErrorNube(
          'La factura no está pendiente o no tiene cliente y plazo configurados.',
        );
        return;
      }
      if (!mounted) return;
      final entry = PaymentCalendarEntry(
        reminderId: '',
        facturaId: invoice.facturaId,
        invoiceNumber: invoice.invoiceNumber,
        cliente: invoice.cliente,
        nombreComercial: invoice.nombreComercial,
        invoiceDate: invoice.invoiceDate,
        reminderDate: invoice.reminderDate ?? invoice.invoiceDate,
        balance: invoice.balance,
      );
      final edit = await showRescheduleReminderDialog(context, entry);
      if (edit == null || !mounted) return;
      await repository.scheduleInvoice(
        facturaId: fila.referencia,
        date: edit.date,
        comment: edit.comment,
      );
      paymentCalendarRefresh.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Factura reprogramada correctamente.')),
      );
    } catch (_) {
      _mostrarErrorNube(
        'No fue posible reprogramar la factura. Actualiza e inténtalo nuevamente.',
      );
    }
  }

  Future<void> _eliminarAbono(
    FilaVenta fila,
    int indice,
    Abono esperado, {
    String? mesReporte,
  }) async {
    late final FilaVenta confirmada;
    try {
      confirmada = await _supabaseReportes.eliminarAbono(
          fila, mesReporte ?? _reportes.activo.nombre, indice, esperado);
      if (mesReporte == null) {
        await _actualizarConsumidoresDeAbonos();
      } else {
        await _cargarReportes();
        if (mounted) setState(() => _versionCobrosMensuales++);
      }
    } catch (_) {
      if (!mounted) return;
      _mostrarErrorNube(
          'No fue posible eliminar el abono. Pudo cambiar en otro dispositivo; actualiza e inténtalo nuevamente.');
      return;
    }
    if (!mounted) return;
    setState(() {
      fila.abonos
        ..clear()
        ..addAll(confirmada.abonos);
      if (mesReporte == null) _asegurarFilaVacia();
    });
    if (mesReporte == null) await _guardarProgreso();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Abono eliminado correctamente.')));
  }

  Future<void> _agregarAbono(FilaVenta fila, {String? mesReporte}) async {
    await _editarAbono(
      fila,
      fila.abonos.length,
      nuevo: true,
      mesReporte: mesReporte,
    );
  }

  Future<void> _gestionarAbonosAdicionales(
    FilaVenta fila, {
    String? mesReporte,
  }) async {
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
                    onTap: fila.anulada
                        ? null
                        : () async {
                            await _editarAbono(
                              fila,
                              indice,
                              mesReporte: mesReporte,
                            );
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
              onPressed: fila.anulada
                  ? null
                  : () async {
                      await _agregarAbono(fila, mesReporte: mesReporte);
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
    _navigate(ReportDestination.sellers);
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
    var mes = _reportes.activo.id;
    var desde = mes;
    var hasta = mes;
    var porRango = false;
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
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Descargar por rango'),
                  value: porRango,
                  onChanged: (value) => actualizar(() {
                    porRango = value ?? false;
                    desde = mes;
                    hasta = mes;
                  }),
                ),
                const SizedBox(height: 12),
                if (!porRango)
                  DropdownButtonFormField<String>(
                    initialValue: mes,
                    decoration: const InputDecoration(
                        labelText: 'Mes', border: OutlineInputBorder()),
                    items: _reportes.reportes
                        .map((r) => DropdownMenuItem(
                            value: r.id, child: Text(r.nombre)))
                        .toList(),
                    onChanged: (v) => actualizar(() => mes = v ?? mes),
                  )
                else
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
                          onChanged: (v) =>
                              actualizar(() => desde = v ?? desde),
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
                          onChanged: (v) =>
                              actualizar(() => hasta = v ?? hasta),
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
    if (!porRango) {
      desde = mes;
      hasta = mes;
    }
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
    if (reportes.isEmpty) {
      _mostrarErrorNube('No existe información para el período seleccionado.');
      return;
    }
    // Deliberadamente no usamos `ReporteMensual.filas`: esa lista solo tiene
    // los meses abiertos por la interfaz. La exportación siempre parte de un
    // snapshot explícito de Supabase.
    List<FilaVenta> todas;
    try {
      todas = await _supabaseReportes
          .obtenerFilasParaReportes(reportes.map((r) => r.nombre));
    } catch (error) {
      _mostrarErrorNube('No se pudieron consultar los datos del PDF: $error');
      return;
    }
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
      final resultado = await _exporter.guardar(
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
      ).showSnackBar(SnackBar(content: Text(resultado.confirmationMessage)));
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
                    DropdownMenuItem(
                      value: 'anuladas',
                      child: Text('Anuladas'),
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
      _actualizarFiltros(() {
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
      return item.value.referencia.toLowerCase().contains(texto) ||
          item.value.numeroFactura.toLowerCase().contains(texto) ||
          item.value.cliente.toLowerCase().contains(texto) ||
          item.value.nombreComercial.toLowerCase().contains(texto) ||
          item.value.vendedor.toLowerCase().contains(texto);
    }).where((item) {
      if (_filtroVendedor.isNotEmpty &&
          !(_filtroVendedor == _opcionAnulada && item.value.anulada) &&
          item.value.vendedor != _filtroVendedor) {
        return false;
      }
      if (_filtroPlazo == 'sin_establecer' &&
          item.value.paymentTermDays != null) {
        return false;
      }
      if (_filtroPlazo.isNotEmpty &&
          _filtroPlazo != 'sin_establecer' &&
          item.value.paymentTermDays?.toString() != _filtroPlazo) {
        return false;
      }
      return switch (_filtroEstado) {
        'pagados' => item.value.pagada,
        'pendientes' =>
          item.value.tieneDatos && !item.value.pagada && !item.value.anulada,
        'anuladas' => item.value.anulada,
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
        final comparacion = columna == 'referencia'
            ? compareInvoiceReferences(
                izquierda.toString(),
                derecha.toString(),
              )
            : izquierda is num && derecha is num
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
        'referencia' => fila.referencia,
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
    _actualizarFiltros(() {
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
                _actualizarFiltros(() {
                  _ordenColumna = columna;
                  _ordenAscendente = accion == 'asc';
                });
              } else if (accion == 'filter') {
                _filtrarColumna(columna, titulo);
              } else {
                _actualizarFiltros(() => _filtrosColumnas.remove(columna));
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

  List<FilaVenta> get _filasParaTotales =>
      _filasVisibles.map((item) => item.value).toList();
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

  // ignore: unused_element
  String get _descripcionFiltro {
    final partes = <String>[];
    if (_filtro.isNotEmpty) partes.add('Texto: $_filtro');
    if (_filtroVendedor.isNotEmpty) {
      partes.add('Vendedor: $_filtroVendedor');
    }
    if (_filtroEstado == 'pagados') partes.add('Pagados al 100%');
    if (_filtroEstado == 'pendientes') partes.add('Pendientes');
    if (_filtroEstado == 'anuladas') partes.add('Anuladas');
    if (_filtrosColumnas.isNotEmpty) {
      partes.add('${_filtrosColumnas.length} filtro(s) de columna');
    }
    return partes.join(' · ');
  }

  Widget _busquedaGeneral() => GeneralSearchScreen(
        onOpenDetail: (invoice) => _abrirDetalleFactura(
          invoice.row,
          mesReporte: invoice.reportMonth,
        ),
        onEditPayment: (invoice, index, {required isNew}) => _editarAbono(
          invoice.row,
          index,
          nuevo: isNew,
          mesReporte: invoice.reportMonth,
        ),
        onManageAdditionalPayments: (invoice) => _gestionarAbonosAdicionales(
          invoice.row,
          mesReporte: invoice.reportMonth,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_esReleaseMovil) return _vistaMovil();

    return Scaffold(
      body: Column(
        children: [
          _barraSuperior(),
          Expanded(
            child: _vistaCatalogos
                ? const CatalogsScreen()
                : _vistaCalendario
                    ? PaymentCalendarView(
                        key: ValueKey(widget.calendarRequestId),
                        initialMonth: widget.initialCalendarDate,
                        initialDate: widget.initialCalendarDate,
                        onPaymentPersisted: _actualizarConsumidoresDeAbonos,
                        onOpenInvoiceDetail: _abrirDetalleDesdePerfil)
                    : _vistaCargaFacturas
                        ? CargaFacturasView(
                            key: ValueKey(_reportes.activo.id),
                            mes: _reportes.activo.mes,
                            anio: _reportes.activo.anio,
                            onVolver: _goBack,
                            onFacturasGuardadas: _actualizarDesdeSupabase,
                            vendedores: _vendedores.vendedores,
                          )
                        : _vistaClientes
                            ? ClientesScreen(
                                onToggleTheme: widget.onCambiarTema,
                                onOpenInvoiceDetail: _abrirDetalleDesdePerfil)
                            : _vistaBusquedaGeneral
                                ? _busquedaGeneral()
                                : _vistaVendedores
                                    ? VendedoresContent(store: _vendedores)
                                    : _vistaEstadisticas
                                        ? const EstadisticasScreen()
                                        : _vistaCobrosMensuales
                                            ? CobrosMensualesView(
                                                key: ValueKey(
                                                    _versionCobrosMensuales),
                                              )
                                            : LayoutBuilder(
                                                builder:
                                                    (context, constraints) {
                                                  final layout =
                                                      ReportResponsiveLayout
                                                          .forWidth(
                                                    constraints.maxWidth,
                                                  );
                                                  return ReportDesktopFrame(
                                                    layout: layout,
                                                    header: _encabezadoPagina(
                                                        layout),
                                                    kpis: _tarjetasResumen(
                                                        layout),
                                                    toolbar: _barraRedisenada(
                                                        layout),
                                                    table: _tarjetaTabla(),
                                                  );
                                                },
                                              ),
          ),
        ],
      ),
    );
  }

  bool get _esReleaseMovil =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // ignore: unused_element
}
