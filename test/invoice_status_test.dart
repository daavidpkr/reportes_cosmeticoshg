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

  test('cubre los seis estados sintéticos solicitados', () {
    final today = DateTime(2026, 2, 1);
    expect(
      invoiceStatus(invoice(), scheduledDate: DateTime(2026, 2, 2), now: today),
      InvoiceStatus.pending,
    );
    expect(
      invoiceStatus(invoice(paid: 20),
          scheduledDate: DateTime(2026, 2, 2), now: today),
      InvoiceStatus.partial,
    );
    expect(
      invoiceStatus(invoice(paid: 20),
          scheduledDate: DateTime(2026, 1, 31), now: today),
      InvoiceStatus.overdue,
    );
    expect(
      invoiceStatus(invoice(),
          scheduledDate: DateTime(2026, 1, 31), now: today),
      InvoiceStatus.overdue,
    );
    expect(invoiceStatus(invoice(paid: 100), now: today), InvoiceStatus.paid);
    expect(invoiceStatus(invoice(seller: 'ANULADA'), now: today),
        InvoiceStatus.cancelled);
  });

  test('no vence durante el propio día límite', () {
    expect(
      invoiceStatus(invoice(), now: DateTime(2026, 1, 31, 23, 59)),
      InvoiceStatus.pending,
    );
  });

  test('una factura histórica cambia al variar fecha, saldo o abonos', () {
    final row = invoice();
    expect(
        invoiceStatus(row, now: DateTime(2026, 1, 15)), InvoiceStatus.pending);
    row.abonos.first.valor = 25;
    expect(
        invoiceStatus(row, now: DateTime(2026, 1, 15)), InvoiceStatus.partial);
    expect(
        invoiceStatus(row, now: DateTime(2026, 2, 1)), InvoiceStatus.overdue);
    row.abonos.first.valor = 100;
    expect(invoiceStatus(row, now: DateTime(2026, 2, 1)), InvoiceStatus.paid);
  });

  test('calcula el vencimiento histórico sin backfill', () {
    expect(invoiceDueDate(invoice()), DateTime(2026, 1, 31));
  });
}
