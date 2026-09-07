import 'dart:async';

import 'package:cosmeticos_hg_reportes/models/fila_venta.dart';
import 'package:cosmeticos_hg_reportes/screens/general_search_screen.dart';
import 'package:cosmeticos_hg_reportes/screens/reporte/report_invoice_table.dart';
import 'package:cosmeticos_hg_reportes/services/supabase_reportes_service.dart';
import 'package:cosmeticos_hg_reportes/theme/hg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GlobalInvoiceRow invoice({
  String reference = '0002',
  String month = 'Julio 2026',
  int number = 7,
  List<Abono>? payments,
}) =>
    GlobalInvoiceRow(
      reportMonth: month,
      row: FilaVenta(
        numero: number,
        referencia: reference,
        cliente: 'Cliente Uno',
        nombreComercial: 'Comercial Uno',
        fecha: '2026-07-15',
        numeroFactura: 'FAC-2',
        vendedor: '01 - Ana',
        esmalte: 3,
        venta: 100,
        abonos: payments ?? [Abono(valor: 20), Abono()],
      ),
    );

Widget app({
  required GlobalInvoiceSearch search,
  GlobalPaymentEditor? edit,
  GlobalAdditionalPayments? additional,
}) =>
    MaterialApp(
      theme: ThemeData(extensions: const [HgThemeColors.light]),
      home: Scaffold(
        body: GeneralSearchScreen(
          search: search,
          onEditPayment:
              edit ?? (invoice, index, {required isNew}) async => false,
          onManageAdditionalPayments: additional ?? (invoice) async {},
        ),
      ),
    );

void main() {
  testWidgets('uses the canonical complete report table', (tester) async {
    await tester.pumpWidget(app(
      search: (_, {required offset, required limit}) async => [invoice()],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ReportInvoiceTable), findsOneWidget);
    for (final label
        in ReportInvoiceTable.columnLabels.where((e) => e.isNotEmpty)) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Julio 2026'), findsNothing);
    expect(find.byTooltip('Mes original: Julio 2026'), findsOneWidget);
    expect(find.text('Añadir'), findsOneWidget);
    expect(find.text(r'$20.00'), findsWidgets);
    expect(find.text(r'$80.00'), findsOneWidget);
  });

  testWidgets('debounces searches and ignores obsolete responses',
      (tester) async {
    final calls = <String>[];
    final first = Completer<List<GlobalInvoiceRow>>();
    final second = Completer<List<GlobalInvoiceRow>>();
    Future<List<GlobalInvoiceRow>> search(
      String query, {
      required int offset,
      required int limit,
    }) async {
      calls.add(query);
      if (query == 'primera') return first.future;
      if (query == 'segunda') return second.future;
      return [];
    }

    await tester.pumpWidget(app(search: search));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('global-search-field')), 'primera');
    await tester.pump(const Duration(milliseconds: 349));
    expect(calls, ['']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, ['', 'primera']);

    await tester.enterText(
        find.byKey(const ValueKey('global-search-field')), 'segunda');
    await tester.pump(const Duration(milliseconds: 350));
    second.complete([invoice(reference: '22')]);
    await tester.pump();
    expect(find.text('22'), findsOneWidget);

    first.complete([invoice(reference: '11')]);
    await tester.pump();
    expect(find.text('22'), findsOneWidget);
    expect(find.text('11'), findsNothing);
  });

  testWidgets('pages in groups of 50', (tester) async {
    final offsets = <int>[];
    await tester.pumpWidget(app(
      search: (_, {required offset, required limit}) async {
        offsets.add(offset);
        if (offset == 0) {
          return List.generate(
            50,
            (index) => invoice(reference: '${index + 1}', number: index + 1),
          );
        }
        return [invoice(reference: '51', number: 51)];
      },
    ));
    await tester.pumpAndSettle();
    expect(offsets, [0]);

    final loadMore = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cargar más'),
    );
    loadMore.onPressed!();
    await tester.pumpAndSettle();
    expect(offsets, [0, 50]);
    expect(find.text('51'), findsWidgets);
  });

  testWidgets('routes payment and additional actions with monthly context',
      (tester) async {
    final actions = <String>[];
    final value = invoice(
      month: 'Marzo 2025',
      payments: [Abono(), Abono(), Abono(valor: 5)],
    );
    await tester.pumpWidget(app(
      search: (_, {required offset, required limit}) async => [value],
      edit: (item, index, {required isNew}) async {
        actions.add('${item.reportMonth}:$index:$isNew');
        item.row.abonos[index].valor = 25;
        return true;
      },
      additional: (item) async => actions.add('${item.reportMonth}:additional'),
    ));
    await tester.pumpAndSettle();

    final firstPayment = tester.widget<OutlinedButton>(find.byKey(
      const ValueKey('global-payment-Marzo 2025-7-0'),
    ));
    firstPayment.onPressed!();
    await tester.pumpAndSettle();
    final additional = tester.widget<IconButton>(find.byKey(
      const ValueKey('global-additional-Marzo 2025-7'),
    ));
    additional.onPressed!();
    await tester.pumpAndSettle();

    expect(actions, ['Marzo 2025:0:false', 'Marzo 2025:additional']);
    expect(find.text(r'$25.00'), findsOneWidget);
  });
}
