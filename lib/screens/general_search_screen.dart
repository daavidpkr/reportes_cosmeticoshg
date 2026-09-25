import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/supabase_reportes_service.dart';
import '../theme/hg_theme.dart';
import 'reporte/report_invoice_table.dart';
import 'reporte/report_responsive_layout.dart';

typedef GlobalInvoiceSearch = Future<List<GlobalInvoiceRow>> Function(
  String query, {
  required int offset,
  required int limit,
});
typedef GlobalPaymentEditor = Future<bool> Function(
  GlobalInvoiceRow invoice,
  int index, {
  required bool isNew,
});
typedef GlobalAdditionalPayments = Future<void> Function(
    GlobalInvoiceRow invoice);

class GeneralSearchScreen extends StatefulWidget {
  const GeneralSearchScreen({
    required this.onEditPayment,
    required this.onManageAdditionalPayments,
    this.search,
    this.useMobileCards,
    super.key,
  });

  final GlobalInvoiceSearch? search;
  final GlobalPaymentEditor onEditPayment;
  final GlobalAdditionalPayments onManageAdditionalPayments;
  final bool? useMobileCards;

  @override
  State<GeneralSearchScreen> createState() => _GeneralSearchScreenState();
}

class _GeneralSearchScreenState extends State<GeneralSearchScreen> {
  static const pageSize = 50;
  final _controller = TextEditingController();
  SupabaseReportesService? _service;
  Timer? _debounce;
  int _generation = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  final _rows = <GlobalInvoiceRow>[];

  GlobalInvoiceSearch get _search =>
      widget.search ??
      (_service ??= SupabaseReportesService()).buscarFilasGlobales;

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _clearResults() {
    _debounce?.cancel();
    _generation++;
    setState(() {
      _rows.clear();
      _loading = false;
      _hasMore = true;
      _error = null;
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _generation++;
    if (value.trim().isEmpty) {
      _clearResults();
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _load(replace: true),
    );
    setState(() {});
  }

  Future<void> _load({required bool replace}) async {
    if ((!replace && _loading) || (!replace && !_hasMore)) return;
    final query = _controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.isEmpty) {
      _clearResults();
      return;
    }
    final generation = replace ? ++_generation : _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final from = replace ? 0 : _rows.length;
      final page = await _search(query, offset: from, limit: pageSize);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (replace) _rows.clear();
        _rows.addAll(page);
        _hasMore = page.length == pageSize;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = 'No se pudo buscar facturas.');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String _referenceWithoutZeros(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '';
    return int.tryParse(clean)?.toString() ?? clean;
  }

  Future<void> _editPayment(GlobalInvoiceRow invoice, int index) async {
    final changed = await widget.onEditPayment(invoice, index, isNew: false);
    if (changed && mounted) await _load(replace: true);
  }

  Future<void> _managePayments(GlobalInvoiceRow invoice) async {
    await widget.onManageAdditionalPayments(invoice);
    if (mounted) await _load(replace: true);
  }

  Widget _paymentButton(GlobalInvoiceRow invoice, int index, double scale) {
    final payment = invoice.row.abonos[index];
    return ReportPaymentButton(
      payment: payment,
      tooltip: payment.valor == 0
          ? 'Añadir abono · ${invoice.reportMonth}'
          : 'Número de recibo: '
              '${payment.numeroRecibo?.toString() ?? 'Sin número de recibo (registro histórico)'}\n'
              'Comentario: ${payment.comentario.isEmpty ? 'Sin comentario' : payment.comentario}',
      buttonKey: ValueKey(
        'global-payment-${invoice.reportMonth}-${invoice.row.numero}-$index',
      ),
      fontSize: 14 * scale,
      onPressed:
          invoice.row.anulada ? null : () => _editPayment(invoice, index),
    );
  }

  Widget _additionalButton(GlobalInvoiceRow invoice, {double scale = 1}) {
    final row = invoice.row;
    return SizedBox(
      width: 42 * scale,
      height: ReportPaymentButton.touchHeight,
      child: IconButton.filledTonal(
        key: ValueKey('global-additional-${invoice.reportMonth}-${row.numero}'),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        tooltip: row.abonos.length > 2
            ? 'Ver o añadir abonos (${row.abonos.length - 2})'
            : 'Añadir otro abono a esta fila',
        onPressed: () => _managePayments(invoice),
        icon: Badge(
          isLabelVisible: row.abonos.length > 2,
          label: Text('${row.abonos.length - 2}'),
          child: Icon(Icons.add, size: 20 * scale),
        ),
      ),
    );
  }

  Widget _longText(String value, double width) => Tooltip(
        message: value,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      );

  Widget _fitText(String value, {TextStyle? style}) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value, maxLines: 1, style: style),
      );

  DataRow _row(BuildContext context, GlobalInvoiceRow invoice,
      ReportTableGeometry geometry, double scale) {
    final row = invoice.row;
    return DataRow(
      key: ValueKey(
          'global-${invoice.reportMonth}-${row.numero}-${row.referencia}'),
      color: row.anulada
          ? WidgetStatePropertyAll(context.hg.danger.withValues(alpha: .12))
          : row.pagada
              ? WidgetStatePropertyAll(
                  context.hg.positive.withValues(alpha: .12))
              : null,
      cells: [
        DataCell(SizedBox(
            width: 24 * scale,
            child: Text('${row.numero}', textAlign: TextAlign.center))),
        DataCell(Tooltip(
          message: 'Mes original: ${invoice.reportMonth}',
          child: SizedBox(
              width: 72 * scale,
              child: Text(_referenceWithoutZeros(row.referencia))),
        )),
        DataCell(_longText(row.cliente, geometry.clientWidth)),
        DataCell(_longText(row.nombreComercial, geometry.businessNameWidth)),
        DataCell(_fitText(row.fecha)),
        DataCell(_fitText(row.numeroFactura)),
        DataCell(ConstrainedBox(
          constraints: BoxConstraints(maxWidth: geometry.sellerWidth),
          child: Text(row.vendedor, overflow: TextOverflow.ellipsis),
        )),
        DataCell(_fitText('${row.esmalte}')),
        DataCell(_fitText(
            row.anulada ? 'ANULADA' : '\$${row.venta.toStringAsFixed(2)}')),
        DataCell(_paymentButton(invoice, 0, scale)),
        DataCell(_paymentButton(invoice, 1, scale)),
        DataCell(_additionalButton(invoice, scale: scale)),
        DataCell(_fitText(row.anulada
            ? 'ANULADA'
            : '\$${row.totalAbonos.toStringAsFixed(2)}')),
        DataCell(_fitText(
          row.anulada ? 'ANULADA' : '\$${row.saldo.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        )),
      ],
    );
  }

  Widget _detail(String label, String value, {bool emphasized = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 116,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                style: emphasized
                    ? const TextStyle(fontWeight: FontWeight.bold)
                    : null),
          ),
        ]),
      );

  Widget _mobileCard(BuildContext context, GlobalInvoiceRow invoice) {
    final row = invoice.row;
    final status = row.anulada
        ? 'ANULADA'
        : row.pagada
            ? 'PAGADA'
            : 'PENDIENTE';
    final statusColor = row.anulada
        ? context.hg.danger
        : row.pagada
            ? context.hg.positive
            : context.hg.warning;
    return Card(
      key: ValueKey(
          'global-card-${invoice.reportMonth}-${row.numero}-${row.referencia}'),
      margin: const EdgeInsets.only(bottom: 12),
      color: statusColor.withValues(alpha: .07),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('Ref. ${_referenceWithoutZeros(row.referencia)}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(status),
              side: BorderSide(color: statusColor),
            ),
          ]),
          Text('${invoice.reportMonth} · Fila ${row.numero}',
              style: Theme.of(context).textTheme.bodySmall),
          const Divider(height: 24),
          _detail('Cliente', row.cliente),
          _detail('Nombre comercial', row.nombreComercial),
          _detail('Fecha', row.fecha),
          _detail('Nro. factura', row.numeroFactura),
          _detail('Vendedor', row.vendedor),
          _detail('Esmaltes', '${row.esmalte}'),
          _detail('Venta',
              row.anulada ? 'ANULADA' : '\$${row.venta.toStringAsFixed(2)}'),
          const SizedBox(height: 4),
          Text('Abonos', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _paymentButton(invoice, 0, 1),
              _paymentButton(invoice, 1, 1),
              _additionalButton(invoice),
            ],
          ),
          const Divider(height: 24),
          _detail(
              'Total abonado',
              row.anulada
                  ? 'ANULADA'
                  : '\$${row.totalAbonos.toStringAsFixed(2)}'),
          _detail('Saldo',
              row.anulada ? 'ANULADA' : '\$${row.saldo.toStringAsFixed(2)}',
              emphasized: true),
        ]),
      ),
    );
  }

  Widget? get _footer => _hasMore || _error != null
      ? Padding(
          padding: const EdgeInsets.all(12),
          child: TextButton.icon(
            onPressed: _loading ? null : () => _load(replace: false),
            icon: _loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.expand_more),
            label: Text(_error == null ? 'Cargar más' : 'Reintentar'),
          ),
        )
      : null;

  Widget _results(BuildContext context, ReportResponsiveLayout layout,
      ReportTableGeometry geometry) {
    final useMobileCards = widget.useMobileCards ??
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    if (useMobileCards) {
      return ListView(
        key: const ValueKey('global-search-cards'),
        children: [
          ..._rows.map((invoice) => _mobileCard(context, invoice)),
          if (_footer case final footer?) footer,
        ],
      );
    }
    return ReportTableContentFrame(
      minimumWidth: geometry.tableWidth,
      table: ReportInvoiceTable(
        mode: ReportInvoiceTableMode.globalSearch,
        geometry: geometry,
        scale: layout.tableScale,
        headingFontSize: layout.tableHeadingFontSize,
        dataFontSize: layout.tableFontSize,
        headerBuilder: (label, _) => Text(label),
        rows: _rows
            .map((item) => _row(context, item, geometry, layout.tableScale))
            .toList(growable: false),
      ),
      footer: _footer,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final layout = ReportResponsiveLayout.forWidth(constraints.maxWidth);
          final geometry = layout.table;
          return Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Búsqueda general',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('global-search-field'),
                controller: _controller,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText:
                      'Buscar por referencia, factura, cliente o nombre comercial',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _controller.clear();
                            _clearResults();
                          },
                        ),
                ),
              ),
              const SizedBox(height: 12),
              if (_loading && _rows.isEmpty)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null && _rows.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: () => _load(replace: true),
                        child: const Text('Reintentar'),
                      ),
                    ]),
                  ),
                )
              else if (_rows.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(_controller.text.trim().isEmpty
                        ? 'Escribe para buscar una factura'
                        : 'No existen resultados.'),
                  ),
                )
              else
                Expanded(child: _results(context, layout, geometry)),
            ]),
          );
        },
      );
}
