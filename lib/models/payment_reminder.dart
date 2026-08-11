class PaymentReminder {
  const PaymentReminder({
    required this.id,
    required this.facturaId,
    required this.paymentDate,
    required this.active,
    required this.notifyThreeDays,
    required this.notifyOneDay,
    this.scheduleVersion = '',
  });

  final String id;
  final String facturaId;
  final DateTime paymentDate;
  final bool active;
  final bool notifyThreeDays;
  final bool notifyOneDay;
  final String scheduleVersion;

  factory PaymentReminder.fromJson(Map<String, dynamic> json) =>
      PaymentReminder(
        id: json['id']?.toString() ?? '',
        facturaId: json['factura_id']?.toString() ?? '',
        paymentDate: DateTime.parse(json['payment_date'].toString()),
        active: json['active'] as bool? ?? true,
        notifyThreeDays: json['notify_three_days'] as bool? ?? true,
        notifyOneDay: json['notify_one_day'] as bool? ?? true,
        scheduleVersion: json['schedule_version']?.toString() ?? '',
      );
}

DateTime effectiveBusinessDate(DateTime value) {
  final date = DateTime(value.year, value.month, value.day);
  return switch (date.weekday) {
    DateTime.saturday => date.add(const Duration(days: 2)),
    DateTime.sunday => date.add(const Duration(days: 1)),
    _ => date,
  };
}

bool isWeekendAdjustment(DateTime value) =>
    effectiveBusinessDate(value) !=
    DateTime(value.year, value.month, value.day);

class PaymentFollowup {
  const PaymentFollowup({
    required this.id,
    required this.reminderId,
    required this.actionType,
    required this.createdAt,
    this.comment,
    this.previousPaymentDate,
    this.requestedPaymentDate,
    this.effectivePaymentDate,
    this.createdBy,
  });

  final String id;
  final String reminderId;
  final String? comment;
  final String actionType;
  final DateTime createdAt;
  final DateTime? previousPaymentDate;
  final DateTime? requestedPaymentDate;
  final DateTime? effectivePaymentDate;
  final String? createdBy;

  factory PaymentFollowup.fromJson(Map<String, dynamic> json) =>
      PaymentFollowup(
        id: json['id'].toString(),
        reminderId: json['reminder_id'].toString(),
        comment: json['comment']?.toString(),
        actionType: json['action_type'].toString(),
        createdAt: DateTime.parse(json['created_at'].toString()),
        previousPaymentDate: _optionalDate(json['previous_payment_date']),
        requestedPaymentDate: _optionalDate(json['requested_payment_date']),
        effectivePaymentDate: _optionalDate(json['effective_payment_date']),
        createdBy: json['created_by']?.toString(),
      );

  static DateTime? _optionalDate(Object? value) =>
      value == null ? null : DateTime.parse(value.toString());
}

class FollowupResult {
  const FollowupResult({
    required this.actionType,
    required this.effectivePaymentDate,
  });
  final String actionType;
  final DateTime effectivePaymentDate;
  bool get rescheduled => actionType != 'comment';
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
