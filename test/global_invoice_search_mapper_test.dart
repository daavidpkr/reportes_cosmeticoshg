import 'package:cosmeticos_hg_reportes/services/supabase_reportes_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps complete global row and preserves its original month and row', () {
    final result = globalInvoiceRowFromJson({
      'mes_reporte': 'Enero 2024',
      'nro_fila': 19,
      'ref_fact': '00019',
      'nro_fact': 'FAC-19',
      'cliente': 'Cliente',
      'nombre_comercial': 'Comercial',
      'fecha': '2024-01-20',
      'vendedor': '02 - Luis',
      'esmaltes': 4,
      'venta': 90,
      'abonos': [20, 30, 5],
      'numeros_recibo': [100, null, 102],
      'comentarios_abonos': ['uno', '', 'tres'],
      'plazo_pago_dias': 30,
      'fecha_programada': '2024-02-19',
    });

    expect(result.reportMonth, 'Enero 2024');
    expect(result.row.numero, 19);
    expect(result.row.referencia, '00019');
    expect(result.row.numeroFactura, 'FAC-19');
    expect(result.row.totalAbonos, 55);
    expect(result.row.saldo, 35);
    expect(result.row.abonos[2].numeroRecibo, 102);
    expect(result.row.abonos[2].comentario, 'tres');
    expect(result.row.paymentTermDays, 30);
    expect(result.paymentDate, DateTime(2024, 2, 19));
  });

  test('maps canonical detail with payment dates and scheduling state', () {
    final result = invoiceDetailSnapshotFromJson({
      'reference': '00019',
      'invoice_number': '001-002-000000019',
      'invoice_date': '2026-10-01',
      'cliente': 'Cliente',
      'commercial_name': 'Comercial',
      'seller': 'Ana',
      'sale': 100,
      'report_month': 'OCTUBRE 2026',
      'row_number': 4,
      'nail_polish': 0,
      'abonos': [25],
      'payment_receipts': [88],
      'payment_comments': ['Transferencia'],
      'payment_dates': ['2026-10-15'],
      'payment_term_days': 30,
      'scheduled_date': '2026-10-31',
      'next_collection_date': '2026-10-31',
      'schedule_source': 'customer_term',
      'overdue': true,
    });

    expect(result.invoice.numeroFactura, '001-002-000000019');
    expect(result.invoice.abonos.first.fecha, DateTime(2026, 10, 15));
    expect(result.invoice.totalAbonos, 25);
    expect(result.invoice.saldo, 75);
    expect(result.invoice.paymentTermDays, 30);
    expect(result.scheduledDate, DateTime(2026, 10, 31));
    expect(result.nextCollectionDate, DateTime(2026, 10, 31));
    expect(result.scheduleSource, 'customer_term');
    expect(result.overdue, isTrue);
  });
}
