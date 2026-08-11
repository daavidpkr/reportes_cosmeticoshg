import 'package:cosmeticos_hg_reportes/models/payment_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

PaymentReminder reminder(
        {required DateTime date,
        bool active = true,
        bool three = true,
        bool one = true,
        String id = 'r1'}) =>
    PaymentReminder(
        id: id,
        facturaId: 'FAC-1',
        paymentDate: date,
        active: active,
        notifyThreeDays: three,
        notifyOneDay: one);

void main() {
  test('ajusta únicamente sábados y domingos al lunes', () {
    expect(effectiveBusinessDate(DateTime(2026, 8, 10)), DateTime(2026, 8, 10));
    expect(effectiveBusinessDate(DateTime(2026, 8, 14)), DateTime(2026, 8, 14));
    expect(effectiveBusinessDate(DateTime(2026, 8, 15)), DateTime(2026, 8, 17));
    expect(effectiveBusinessDate(DateTime(2026, 8, 16)), DateTime(2026, 8, 17));
  });
  final today = DateTime(2026, 8, 10);
  test('calcula el aviso de tres días', () {
    expect(
        noticeDue(
            today: today, reminder: reminder(date: DateTime(2026, 8, 13))),
        PaymentNotice.threeDays);
  });
  test('calcula el aviso de un día', () {
    expect(
        noticeDue(
            today: today, reminder: reminder(date: DateTime(2026, 8, 11))),
        PaymentNotice.oneDay);
  });
  test('ignora fechas vencidas y el día de pago', () {
    expect(
        noticeDue(today: today, reminder: reminder(date: DateTime(2026, 8, 9))),
        isNull);
    expect(noticeDue(today: today, reminder: reminder(date: today)), isNull);
  });
  test('ignora recordatorios desactivados y avisos no elegidos', () {
    expect(
        noticeDue(
            today: today,
            reminder: reminder(date: DateTime(2026, 8, 13), active: false)),
        isNull);
    expect(
        noticeDue(
            today: today,
            reminder: reminder(date: DateTime(2026, 8, 13), three: false)),
        isNull);
  });
  test('una fecha editada se calcula usando el nuevo día', () {
    final edited = reminder(date: DateTime(2026, 8, 11));
    expect(noticeDue(today: today, reminder: edited), PaymentNotice.oneDay);
  });
  test('un recordatorio reactivado vuelve a ser elegible', () {
    expect(
        noticeDue(
            today: today,
            reminder: reminder(date: DateTime(2026, 8, 13), active: true)),
        PaymentNotice.threeDays);
  });
}
