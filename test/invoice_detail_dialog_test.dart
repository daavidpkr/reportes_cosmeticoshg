import 'dart:async';

import 'package:cosmeticos_hg_reportes/models/fila_venta.dart';
import 'package:cosmeticos_hg_reportes/screens/invoice_detail_dialog.dart';
import 'package:cosmeticos_hg_reportes/services/supabase_reportes_service.dart';
import 'package:cosmeticos_hg_reportes/theme/hg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FilaVenta _invoice({String seller = '008 · Esteban'}) => FilaVenta(
      numero: 1,
      referencia: '000000707',
      cliente: 'GETY SALUD Y DIAGNÓSTICO S.A.S.',
      nombreComercial: 'FARMACITY',
      fecha: '26/08/2026',
      numeroFactura: '000000707',
      vendedor: seller,
      venta: 62.50,
      paymentTermDays: 60,
      abonos: [
        Abono(
          valor: 20,
          numeroRecibo: 1048,
          comentario: 'Pago parcial en efectivo',
          fecha: DateTime(2026, 9, 12),
        ),
      ],
    );

InvoiceDetailSnapshot _snapshot(FilaVenta invoice) => InvoiceDetailSnapshot(
      invoice: invoice,
      reportMonth: 'AGOSTO 2026',
      overdue: false,
      scheduledDate: DateTime(2026, 10, 26),
      nextCollectionDate: DateTime(2026, 10, 26),
      scheduleSource: 'manual',
    );

Widget _app({required Widget home}) => MaterialApp(
      theme:
          ThemeData.light().copyWith(extensions: const [HgThemeColors.light]),
      darkTheme:
          ThemeData.dark().copyWith(extensions: const [HgThemeColors.dark]),
      home: Scaffold(body: home),
    );

void main() {
  testWidgets('es modal también en Android y conserva margen exterior',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late BuildContext context;
    await tester.pumpWidget(_app(home: Builder(builder: (value) {
      context = value;
      return FilledButton(
        onPressed: () => showInvoiceDetailDialog(
          context,
          invoice: _invoice(),
          loadDetail: (_) async => _snapshot(_invoice()),
          onPayment: () async {},
          onPayInFull: () async {},
          onReschedule: () async {},
        ),
        child: const Text('Abrir'),
      );
    })));

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    final dialogRect =
        tester.getRect(find.byKey(const ValueKey('invoice-detail-modal')));
    expect(dialogRect.left, greaterThanOrEqualTo(10));
    expect(dialogRect.right, lessThanOrEqualTo(380));
    expect(dialogRect.height, lessThanOrEqualTo(700));
    expect(find.text('Factura 000000707'), findsOneWidget);
    expect(find.text('REF. 707'), findsOneWidget);
    expect(find.text('Abonada'), findsOneWidget);
  });

  testWidgets('enruta las acciones canónicas sin superponer modales',
      (tester) async {
    final calls = <String>[];
    late BuildContext context;
    Future<void> open() => showInvoiceDetailDialog(
          context,
          invoice: _invoice(),
          loadDetail: (_) async => _snapshot(_invoice()),
          onPayment: () async => calls.add('payment'),
          onEditPayment: (index) async => calls.add('edit:$index'),
          onPayInFull: () async => calls.add('full'),
          onReschedule: () async => calls.add('schedule'),
          onViewCustomerProfile: () async {
            calls.add('profile');
            return true;
          },
        );
    await tester.pumpWidget(_app(home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    })));

    for (final action in <(Key, String)>[
      (const ValueKey('add-payment-action'), 'payment'),
      (const ValueKey('edit-payment-0'), 'edit:0'),
      (const ValueKey('pay-in-full-action'), 'full'),
      (const ValueKey('edit-schedule'), 'schedule'),
      (const ValueKey('view-customer-profile'), 'profile'),
    ]) {
      unawaited(open());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(action.$1),
        250,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('invoice-detail-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(action.$1));
      await tester.pumpAndSettle();
      expect(calls.last, action.$2);
      expect(find.byType(Dialog), findsNothing);
    }
  });

  testWidgets('ignora una carga obsoleta después de cerrar', (tester) async {
    final pending = Completer<InvoiceDetailSnapshot?>();
    late BuildContext context;
    await tester.pumpWidget(_app(home: Builder(builder: (value) {
      context = value;
      return FilledButton(
        onPressed: () => showInvoiceDetailDialog(
          context,
          invoice: _invoice(),
          loadDetail: (_) => pending.future,
        ),
        child: const Text('Abrir'),
      );
    })));
    await tester.tap(find.text('Abrir'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('close-invoice-detail')));
    await tester.pumpAndSettle();
    pending.complete(_snapshot(_invoice()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
