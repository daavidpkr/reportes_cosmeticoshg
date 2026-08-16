import 'package:cosmeticos_hg_reportes/models/customer_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('KPI numéricos excluyen anulada y conservan estados', () {
    final page = CustomerHistoryPage.fromJson({
      'summary': {
        'total_sales': 300,
        'total_paid': 150,
        'balance': 150,
        'total_invoices': 3,
        'paid_invoices': 1,
        'pending_invoices': 1,
        'overdue_invoices': 1,
        'cancelled_invoices': 1
      },
      'filtered_count': 3,
      'invoices': [
        {
          'reference': 'A',
          'invoice_number': 'A',
          'invoice_date': '2026-01-01',
          'sale': 100,
          'paid': 100,
          'balance': 0,
          'cancelled': false,
          'overdue': false,
          'payments': [
            {'amount': 100}
          ]
        },
        {
          'reference': 'B',
          'invoice_number': 'B',
          'invoice_date': '2026-02-01',
          'sale': 200,
          'paid': 50,
          'balance': 150,
          'cancelled': false,
          'overdue': true,
          'payments': [
            {'amount': 50, 'receipt': 2, 'comment': 'Parcial'}
          ]
        },
        {
          'reference': 'C',
          'invoice_number': 'C',
          'invoice_date': '2026-03-01',
          'sale': 80,
          'paid': 0,
          'balance': 0,
          'cancelled': true,
          'overdue': false,
          'payments': []
        },
      ]
    });
    expect(page.summary.totalSales, 300);
    expect(page.summary.totalPaid, 150);
    expect(page.summary.balance, 150);
    expect(page.invoices.map((item) => item.status),
        ['Pagada', 'Vencida', 'Anulada']);
    expect(page.invoices[1].payments.single.receiptNumber, 2);
  });
}
