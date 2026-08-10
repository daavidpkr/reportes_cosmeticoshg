class PaymentReminder {
  const PaymentReminder({
    required this.id,
    required this.facturaId,
    required this.paymentDate,
    required this.active,
    required this.notifyThreeDays,
    required this.notifyOneDay,
  });

  final String id;
  final String facturaId;
  final DateTime paymentDate;
  final bool active;
  final bool notifyThreeDays;
  final bool notifyOneDay;

  factory PaymentReminder.fromJson(Map<String, dynamic> json) =>
      PaymentReminder(
        id: json['id']?.toString() ?? '',
        facturaId: json['factura_id']?.toString() ?? '',
        paymentDate: DateTime.parse(json['payment_date'].toString()),
        active: json['active'] as bool? ?? true,
        notifyThreeDays: json['notify_three_days'] as bool? ?? true,
        notifyOneDay: json['notify_one_day'] as bool? ?? true,
      );
}

enum PaymentNotice { threeDays, oneDay }

PaymentNotice? noticeDue(
    {required DateTime today, required PaymentReminder reminder}) {
  if (!reminder.active) return null;
  final current = DateTime(today.year, today.month, today.day);
  final payment = DateTime(reminder.paymentDate.year,
      reminder.paymentDate.month, reminder.paymentDate.day);
  final days = payment.difference(current).inDays;
  if (days == 3 && reminder.notifyThreeDays) return PaymentNotice.threeDays;
  if (days == 1 && reminder.notifyOneDay) return PaymentNotice.oneDay;
  return null;
}
