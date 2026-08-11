import 'package:cosmeticos_hg_reportes/models/billing_customer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calcula desde la fecha de factura y acepta plazo cero', () {
    expect(
        calculatePaymentDate(DateTime(2026, 8, 10), 45), DateTime(2026, 9, 24));
    expect(
        calculatePaymentDate(DateTime(2026, 8, 10), 0), DateTime(2026, 8, 10));
  });

  test('ajusta resultados sábado y domingo al lunes', () {
    expect(
        calculatePaymentDate(DateTime(2026, 8, 14), 1), DateTime(2026, 8, 17));
    expect(
        calculatePaymentDate(DateTime(2026, 8, 14), 2), DateTime(2026, 8, 17));
  });

  test('rechaza negativos, decimales y texto', () {
    expect(parsePaymentTerm('-1'), isNull);
    expect(parsePaymentTerm('1.5'), isNull);
    expect(parsePaymentTerm('treinta'), isNull);
    expect(parsePaymentTerm('0'), 0);
    expect(() => calculatePaymentDate(DateTime(2026), -1), throwsArgumentError);
  });

  test('interpreta fechas de factura conocidas', () {
    expect(parseInvoiceDate('10/08/2026'), DateTime(2026, 8, 10));
    expect(parseInvoiceDate('2026-08-10'), DateTime(2026, 8, 10));
    expect(parseInvoiceDate('fecha inválida'), isNull);
  });

  test('una excepción no modifica el plazo habitual del modelo', () {
    const plan = InvoicePaymentPlan(
      invoiceDate: null,
      customerTermDays: 45,
      exceptionalTermDays: 15,
      currentPaymentDate: null,
      manualSchedule: false,
    );
    expect(plan.customerTermDays, 45);
    expect(plan.applicableDays, 15);
  });
}
