import 'package:cosmeticos_hg_reportes/models/fila_venta.dart';
import 'package:cosmeticos_hg_reportes/models/invoice_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FilaVenta invoice({
    String seller = 'VENDEDOR',
    double sale = 100,
    double paid = 0,
  }) =>
      FilaVenta(
        numero: 1,
        vendedor: seller,
        venta: sale,
        fecha: '2026-01-01',
        paymentTermDays: 30,
        abonos: [Abono(valor: paid), Abono()],
      );

  test('prioridad: anulada, pagada, atrasada y abonada', () {
    final now = DateTime(2026, 3, 1);
    expect(invoiceStatus(invoice(seller: 'ANUL', paid: 100), now: now),
        InvoiceStatus.cancelled);
    expect(invoiceStatus(invoice(paid: 100), now: now), InvoiceStatus.paid);
    expect(invoiceStatus(invoice(paid: 20), now: now), InvoiceStatus.overdue);
    expect(
      invoiceStatus(invoice(paid: 20),
          scheduledDate: DateTime(2026, 3, 2), now: now),
      InvoiceStatus.partial,
    );
  });

  test('calcula el vencimiento histórico sin backfill', () {
    expect(invoiceDueDate(invoice()), DateTime(2026, 1, 31));
  });
}
