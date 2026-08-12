import 'package:cosmeticos_hg_reportes/models/fila_venta.dart';
import 'package:cosmeticos_hg_reportes/services/supabase_reportes_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
