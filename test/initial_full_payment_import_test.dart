import 'dart:io';
import 'dart:typed_data';

import 'package:cosmeticos_hg_reportes/models/factura.dart';
import 'package:cosmeticos_hg_reportes/models/fila_venta.dart';
import 'package:cosmeticos_hg_reportes/screens/carga_facturas_screen.dart';
import 'package:cosmeticos_hg_reportes/services/invoice_batch_importer.dart';
import 'package:cosmeticos_hg_reportes/services/invoice_file_preparer.dart';
import 'package:cosmeticos_hg_reportes/services/supabase_reportes_service.dart';
import 'package:cosmeticos_hg_reportes/services/vendedores_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _invoice = Factura(
  cliente: 'Cliente pago completo',
  nombreComercial: 'Local',
  fecha: '24/10/2026',
  secuencial: '900',
  total: 123.45,
);

ReviewableInvoice _reviewable() => ReviewableInvoice(
      factura: _invoice,
      file: PreparedInvoiceXml(
        name: '900.xml',
        bytes: Uint8List(0),
        fromZip: false,
        sourceName: '900.xml',
      ),
    )
      ..vendedor = '01 - Ana'
      ..termEstablished = true
      ..paymentTermDays = 30;

Future<void> _showReview(
  WidgetTester tester,
  ReviewableInvoice invoice,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InvoiceReviewDialog(
          review: InvoiceBatchReview(
            invoices: [invoice],
            issues: const [],
            fileIssues: const [],
          ),
          requirePaymentTerms: true,
          vendedores: const [Vendedor(codigo: '01', nombre: 'Ana')],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _registerPayment(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('paid-900')));
  await tester.pumpAndSettle();
  final amount = tester.widget<TextFormField>(
    find.byKey(const ValueKey('payment-amount')),
  );
  expect(amount.controller!.text, '123.45');
  expect(
    tester
        .widget<EditableText>(find.descendant(
          of: find.byKey(const ValueKey('payment-amount')),
          matching: find.byType(EditableText),
        ))
        .readOnly,
    isTrue,
  );
  await tester.enterText(
    find.byKey(const ValueKey('payment-receipt')),
    '4587',
  );
  await tester.enterText(
    find.byKey(const ValueKey('payment-comment')),
    'Transferencia',
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('registra, muestra, edita y quita el pago antes de importar',
      (tester) async {
    final invoice = _reviewable();
    await _showReview(tester, invoice);
    await _registerPayment(tester);

    expect(find.text('Se importará pagada'), findsOneWidget);
    expect(invoice.pago?.valor, 123.45);
    expect(invoice.pago?.numeroRecibo, 4587);
    expect(invoice.pago?.comentario, 'Transferencia');

    await tester.tap(find.byKey(const ValueKey('edit-payment-900')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment-receipt')),
      '5001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-comment')),
      'Depósito editado',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(invoice.pago?.comentario, 'Depósito editado');
    expect(invoice.pago?.numeroRecibo, 5001);
    expect(invoice.pago?.valor, 123.45);

    await tester.tap(find.byKey(const ValueKey('remove-payment-900')));
    await tester.pumpAndSettle();
    expect(find.text('Quitar pago completo'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Quitar pago'));
    await tester.pumpAndSettle();
    expect(invoice.pago, isNull);
    expect(find.byKey(const ValueKey('paid-900')), findsOneWidget);
  });

  testWidgets('ANUL exige confirmación y elimina el pago al aceptarla',
      (tester) async {
    final invoice = _reviewable();
    await _showReview(tester, invoice);
    await _registerPayment(tester);

    final seller = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('seller-900')),
    );
    seller.onChanged!('ANUL');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Conservar pago'));
    await tester.pumpAndSettle();
    expect(invoice.vendedor, '01 - Ana');
    expect(invoice.pago, isNotNull);

    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('seller-900')),
        )
        .onChanged!('ANUL');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Quitar pago'));
    await tester.pumpAndSettle();
    expect(invoice.vendedor, 'ANUL');
    expect(invoice.pago, isNull);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('paid-900')))
          .onPressed,
      isNull,
    );
  });

  test('serializa un pago canónico y rechaza pago con ANUL', () {
    final paid = FacturaAsignada(
      factura: _invoice,
      vendedor: '01 - Ana',
      paymentTermDays: 30,
      pago: Abono(
        valor: 123.45,
        numeroRecibo: 4587,
        comentario: 'Transferencia',
      ),
    );
    final params = construirParametrosImportarFacturas(
      facturasAsignadas: [paid],
      anio: 2026,
      mes: 10,
      requestId: '00000000-0000-0000-0000-000000000010',
    );
    final payload = (params['p_invoices'] as List).single;
    expect(payload['abonos'], [123.45]);
    expect(payload['numeros_recibo'], [4587]);
    expect(payload['comentarios_abonos'], ['Transferencia']);
    expect(
        () => validarFacturasAsignadasParaImportacion([paid]), returnsNormally);
    expect(
      () => verificarVendedoresPersistidos(
        esperadas: [paid],
        persistidas: const [
          {
            'ref_fact': '900',
            'vendedor': '01 - Ana',
            'abonos': [123.45],
            'numeros_recibo': [4587],
            'comentarios_abonos': ['Transferencia'],
          },
        ],
      ),
      returnsNormally,
    );
    expect(
      () => verificarVendedoresPersistidos(
        esperadas: [paid],
        persistidas: const [
          {
            'ref_fact': '900',
            'vendedor': '01 - Ana',
            'abonos': [],
            'numeros_recibo': [],
            'comentarios_abonos': [],
          },
        ],
      ),
      throwsStateError,
    );
    expect(
      () => validarFacturasAsignadasParaImportacion([
        FacturaAsignada(
          factura: _invoice,
          vendedor: 'ANUL',
          pago: Abono(valor: 123.45),
        ),
      ]),
      throwsFormatException,
    );
  });

  test('la migración mantiene atomicidad e idempotencia del RPC', () {
    final sql = File(
      'supabase/migrations/'
      '20261024120000_atomic_full_payment_invoice_import.sql',
    ).readAsStringSync();
    expect(sql.trimLeft(), startsWith('begin;'));
    expect(sql.trimRight(), endsWith('commit;'));
    expect(sql, contains('and er.request_id = p_request_id'));
    expect(sql, contains("'import_monthly_invoices'"));
    expect(sql, contains('Validate the complete batch before any'));
    expect(sql, contains("else '[]'::jsonb"));
    expect(sql, contains('elsif public.sync_enterprise_reminder'));
  });
}
