import 'dart:async';

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
  GlobalInvoiceRow invoice,
);

class GeneralSearchScreen extends StatefulWidget {
  const GeneralSearchScreen({
    required this.onEditPayment,
    required this.onManageAdditionalPayments,
    this.search,
    super.key,
  });

  final GlobalInvoiceSearch? search;
  final GlobalPaymentEditor onEditPayment;
  final GlobalAdditionalPayments onManageAdditionalPayments;

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
  void initState() {
    super.initState();
    _load(replace: true);
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _generation++;
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _load(replace: true),
    );
    setState(() {});
  }

  Future<void> _load({required bool replace}) async {
    if ((!replace && _loading) || (!replace && !_hasMore)) return;
    final generation = replace ? ++_generation : _generation;
    final query = _controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
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
      onPressed: invoice.row.anulada
          ? null
          : () async {
              final changed = await widget.onEditPayment(
                invoice,
                index,
                isNew: false,
              );
              if (changed && mounted) setState(() {});
            },
    );
  }

  DataRow _row(
    BuildContext context,
    GlobalInvoiceRow invoice,
    ReportTableGeometry geometry,
    double scale,
  ) {
    final row = invoice.row;
    return DataRow(
      key: ValueKey(
        'global-${invoice.reportMonth}-${row.numero}-${row.referencia}',
      ),
      color: row.anulada
          ? WidgetStatePropertyAll(context.hg.danger.withValues(alpha: .12))
          : row.pagada
              ? WidgetStatePropertyAll(
                  context.hg.positive.withValues(alpha: .12),
                )
              : null,
      cells: [
        DataCell(SizedBox(
          width: 24 * scale,
          child: Text('${row.numero}', textAlign: TextAlign.center),
        )),
        DataCell(Tooltip(
          message: 'Mes original: ${invoice.reportMonth}',
          child: SizedBox(
            width: 72 * scale,
            child: Text(_referenceWithoutZeros(row.referencia)),
          ),
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
          row.anulada ? 'ANULADA' : '\$${row.venta.toStringAsFixed(2)}',
        )),
        DataCell(_paymentButton(invoice, 0, scale)),
        DataCell(_paymentButton(invoice, 1, scale)),
        DataCell(SizedBox(
          width: 42 * scale,
          height: ReportPaymentButton.touchHeight,
          child: IconButton.filledTonal(
            key: ValueKey(
              'global-additional-${invoice.reportMonth}-${row.numero}',
            ),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            tooltip: row.abonos.length > 2
                ? 'Ver o añadir abonos (${row.abonos.length - 2})'
                : 'Añadir otro abono a esta fila',
            onPressed: () async {
              await widget.onManageAdditionalPayments(invoice);
              if (mounted) setState(() {});
            },
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.add, size: 20 * scale),
                if (row.abonos.length > 2)
                  Positioned(
                    right: -9,
                    top: -9,
                    child: CircleAvatar(
                      radius: 8,
                      child: Text(
                        '${row.abonos.length - 2}',
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        )),
        DataCell(_fitText(
          row.anulada ? 'ANULADA' : '\$${row.totalAbonos.toStringAsFixed(2)}',
        )),
        DataCell(_fitText(
          row.anulada ? 'ANULADA' : '\$${row.saldo.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final layout = ReportResponsiveLayout.forWidth(constraints.maxWidth);
          final geometry = layout.table;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Búsqueda general',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
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
                              _generation++;
                              _load(replace: true);
                              setState(() {});
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading && _rows.isEmpty)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null && _rows.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          const SizedBox(height: 8),
                          FilledButton.tonal(
                            onPressed: () => _load(replace: true),
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_rows.isEmpty)
                  const Expanded(
                    child: Center(child: Text('No existen resultados.')),
                  )
                else
                  Expanded(
                    child: ReportTableContentFrame(
                      minimumWidth: geometry.tableWidth,
                      table: ReportInvoiceTable(
                        mode: ReportInvoiceTableMode.globalSearch,
                        geometry: geometry,
                        scale: layout.tableScale,
                        headingFontSize: layout.tableHeadingFontSize,
                        dataFontSize: layout.tableFontSize,
                        headerBuilder: (label, _) => Text(label),
                        rows: _rows
                            .map((item) => _row(
                                  context,
                                  item,
                                  geometry,
                                  layout.tableScale,
                                ))
                            .toList(growable: false),
                      ),
                      footer: _hasMore || _error != null
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: TextButton.icon(
                                onPressed: _loading
                                    ? null
                                    : () => _load(replace: false),
                                icon: _loading
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.expand_more),
                                label: Text(
                                  _error == null ? 'Cargar más' : 'Reintentar',
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          );
        },
      );
}
