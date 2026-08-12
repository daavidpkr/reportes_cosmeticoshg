import 'package:cosmeticos_hg_reportes/models/fila_venta.dart';
import 'package:cosmeticos_hg_reportes/services/supabase_reportes_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a new invoice sends the complete RPC signature with empty arrays', () {
    final params = construirParametrosGuardarFila(
      fila: FilaVenta(
        numero: 1,
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
  });
}
