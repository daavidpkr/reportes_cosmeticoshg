import 'package:flutter/material.dart';

import '../../theme/hg_theme.dart';
import 'report_responsive_layout.dart';

enum ReportInvoiceTableMode { editable, readOnly, globalSearch }

typedef ReportInvoiceHeaderBuilder = Widget Function(
  String label,
  String? filterKey,
);

/// Canonical table used by monthly sales, the consolidated report and global
/// invoice search. Row behavior is supplied by each screen, while geometry,
/// columns and visual formatting remain identical.
class ReportInvoiceTable extends StatelessWidget {
  const ReportInvoiceTable({
    required this.mode,
    required this.geometry,
    required this.scale,
    required this.headingFontSize,
    required this.dataFontSize,
    required this.rows,
    required this.headerBuilder,
    super.key,
  });

  static const columnLabels = <String>[
    'NRO',
    'REF. (FACT)',
    'CLIENTE',
    'NOMBRE COMERCIAL',
    'FECHA',
    'NRO. FACT.',
    'VENDEDOR',
    'ESMALTE',
    'VENTA',
    'ABONO 1',
    'ABONO 2',
    '',
    'TOT. ABONO',
    'SALDO',
  ];

  final ReportInvoiceTableMode mode;
  final ReportTableGeometry geometry;
  final double scale;
  final double headingFontSize;
  final double dataFontSize;
  final List<DataRow> rows;
  final ReportInvoiceHeaderBuilder headerBuilder;

  Widget _header(String label, String? filterKey, double width) => SizedBox(
        width: width,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: headerBuilder(label, filterKey),
        ),
      );

  @override
  Widget build(BuildContext context) => DataTable(
        key: ValueKey('report-data-table-${mode.name}'),
        horizontalMargin: 7 * scale,
        columnSpacing: 10 * scale,
        dataRowMinHeight: 38 * scale,
        dataRowMaxHeight: 58 * scale,
        headingRowHeight: 46 * scale,
        headingRowColor: WidgetStatePropertyAll(context.hg.tableHeader),
        headingTextStyle: TextStyle(
          color: context.hg.mutedText,
          fontWeight: FontWeight.w600,
          letterSpacing: .7,
          fontSize: headingFontSize,
        ),
        dataTextStyle: TextStyle(fontSize: dataFontSize),
        columns: [
          DataColumn(label: _header(columnLabels[0], null, 24 * scale)),
          DataColumn(label: _header(columnLabels[1], null, 72 * scale)),
          DataColumn(
              label: _header(columnLabels[2], 'cliente', geometry.clientWidth)),
          DataColumn(
              label: _header(
                  columnLabels[3], 'nombre', geometry.businessNameWidth)),
          DataColumn(label: _header(columnLabels[4], 'fecha', 72 * scale)),
          DataColumn(label: _header(columnLabels[5], 'factura', 76 * scale)),
          DataColumn(
              label:
                  _header(columnLabels[6], 'vendedor', geometry.sellerWidth)),
          DataColumn(label: _header(columnLabels[7], null, 58 * scale)),
          DataColumn(label: _header(columnLabels[8], 'venta', 64 * scale)),
          DataColumn(label: _header(columnLabels[9], null, 82 * scale)),
          DataColumn(label: _header(columnLabels[10], null, 82 * scale)),
          const DataColumn(label: SizedBox.shrink()),
          DataColumn(label: _header(columnLabels[12], null, 78 * scale)),
          DataColumn(label: _header(columnLabels[13], 'saldo', 68 * scale)),
        ],
        rows: rows,
      );
}
