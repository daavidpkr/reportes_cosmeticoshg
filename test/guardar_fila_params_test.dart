import 'package:cosmeticos_hg_reportes/models/fila_venta.dart';
import 'package:cosmeticos_hg_reportes/models/factura.dart';
import 'package:cosmeticos_hg_reportes/services/supabase_reportes_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('monthly import preserves full references and the selected period', () {
    final params = construirParametrosImportarFacturas(
      facturas: [
        const Factura(
          cliente: 'Cliente',
          nombreComercial: 'Local',
          fecha: '27/07/2026',
          secuencial: '000000656',
          total: 42.5,
        ),
      ],
      anio: 2026,
      mes: 7,
      requestId: '00000000-0000-0000-0000-000000000007',
    );

    expect(params['p_year'], 2026);
    expect(params['p_month'], 7);
    expect((params['p_invoices'] as List).single, {
      'ref_fact': '000000656',
      'nro_fact': '000000656',
      'cliente': 'Cliente',
      'nombre_comercial': 'Local',
      'fecha': '2026-07-27',
      'venta': 42.5,
    });
  });

  test('delete payment uses canonical row and exact aligned tuple', () {
    final payment =
        Abono(valor: 40, numeroRecibo: 6080, comentario: 'Transferencia');
    final params = construirParametrosEliminarAbono(
      fila: FilaVenta(numero: 17, referencia: '000000608'),
      mesReporte: 'Julio 2026',
      indice: 1,
      esperado: payment,
      requestId: '00000000-0000-0000-0000-000000000006',
    );
    expect(params, {
      'p_request_id': '00000000-0000-0000-0000-000000000006',
      'p_row_number': 17,
      'p_report_name': 'Julio 2026',
      'p_payment_index': 1,
      'p_expected_amount': 40,
      'p_expected_receipt': 6080,
      'p_expected_comment': 'Transferencia',
    });
  });

  test('a new invoice sends the complete RPC signature with empty arrays', () {
    final params = construirParametrosGuardarFila(
      fila: FilaVenta(
        numero: 1,
        referencia: 'REF-1',
        numeroFactura: 'FACT-1',
        cliente: 'Cliente',
        fecha: '11/08/2026',
        venta: 25,
      ),
      mesReporte: 'Agosto 2026',
      requestId: '00000000-0000-0000-0000-000000000001',
      invoiceDate: DateTime(2026, 8, 11),
    );

    expect(params['p_payments'], isEmpty);
    expect(params['p_ref_fact'], 'REF-1');
    expect(params['p_invoice_number'], 'FACT-1');
    expect(params['p_payment_receipts'], isEmpty);
    expect(params['p_payment_comments'], isEmpty);
  });

  test('payments, receipts and comments remain aligned', () {
    final params = construirParametrosGuardarFila(
      fila: FilaVenta(
        numero: 1,
        abonos: [
          Abono(valor: 100.50, numeroRecibo: 4587, comentario: 'Transferencia'),
          Abono(valor: 20, comentario: 'Registro anterior'),
          Abono(),
        ],
      ),
      mesReporte: 'Agosto 2026',
      requestId: '00000000-0000-0000-0000-000000000002',
    );

    expect(params['p_payments'], [100.50, 20]);
    expect(params['p_payment_receipts'], [4587, null]);
    expect(
        params['p_payment_comments'], ['Transferencia', 'Registro anterior']);
    expect((params['p_payment_receipts'] as List).first, isA<int>());
  });

  test('removing an intermediate payment removes its aligned tuple', () {
    final fila = FilaVenta(
      numero: 1,
      abonos: [
        Abono(valor: 10, numeroRecibo: 1001, comentario: 'Primero'),
        Abono(valor: 20, numeroRecibo: 1002, comentario: 'Intermedio'),
        Abono(valor: 30, numeroRecibo: 1003, comentario: 'Final'),
      ],
    );
    fila.abonos.removeAt(1);

    final params = construirParametrosGuardarFila(
      fila: fila,
      mesReporte: 'Agosto 2026',
      requestId: '00000000-0000-0000-0000-000000000003',
    );

    expect(params['p_payments'], [10, 30]);
    expect(params['p_payment_receipts'], [1001, 1003]);
    expect(params['p_payment_comments'], ['Primero', 'Final']);
  });

  test('optional receipt and comment keep null positions', () {
    final params = construirParametrosGuardarFila(
      fila: FilaVenta(
        numero: 1,
        abonos: [Abono(valor: 9.90), Abono(valor: 8, comentario: 'Efectivo')],
      ),
      mesReporte: 'Agosto 2026',
      requestId: '00000000-0000-0000-0000-000000000004',
    );

    expect(params['p_payments'], [9.90, 8]);
    expect(params['p_payment_receipts'], [null, null]);
    expect(params['p_payment_comments'], [null, 'Efectivo']);
  });

  test('three mixed receipts preserve their exact indexes', () {
    final params = construirParametrosGuardarFila(
      fila: FilaVenta(
        numero: 1,
        abonos: [
          Abono(valor: 9.90, comentario: 'Sin recibo'),
          Abono(valor: 10, numeroRecibo: 4587, comentario: 'Transferencia'),
          Abono(valor: 11),
        ],
      ),
      mesReporte: 'Agosto 2026',
      requestId: '00000000-0000-0000-0000-000000000005',
    );

    expect(params['p_payments'], [9.90, 10, 11]);
    expect(params['p_payment_receipts'], [null, 4587, null]);
    expect(params['p_payment_comments'], ['Sin recibo', 'Transferencia', null]);
  });
}
