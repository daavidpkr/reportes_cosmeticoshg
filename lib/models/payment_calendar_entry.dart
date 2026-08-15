class PaymentCalendarEntry {
  const PaymentCalendarEntry({
    required this.reminderId,
    required this.facturaId,
    required this.invoiceNumber,
    required this.cliente,
    required this.nombreComercial,
    required this.invoiceDate,
    required this.reminderDate,
    required this.balance,
    this.comment = '',
  });

  final String reminderId;
  final String facturaId;
  final String invoiceNumber;
  final String cliente;
  final String nombreComercial;
  final DateTime invoiceDate;
  final DateTime reminderDate;
  final double balance;
  final String comment;

  PaymentCalendarEntry copyWith({DateTime? reminderDate, String? comment}) =>
      PaymentCalendarEntry(
        reminderId: reminderId,
        facturaId: facturaId,
        invoiceNumber: invoiceNumber,
        cliente: cliente,
        nombreComercial: nombreComercial,
        invoiceDate: invoiceDate,
        reminderDate: reminderDate ?? this.reminderDate,
        balance: balance,
        comment: comment ?? this.comment,
      );

  factory PaymentCalendarEntry.fromJson(Map<String, dynamic> json) =>
      PaymentCalendarEntry(
        reminderId: json['reminder_id'].toString(),
        facturaId: json['factura_id'].toString(),
        invoiceNumber: json['invoice_number']?.toString() ?? '',
        cliente: json['cliente']?.toString() ?? '',
        nombreComercial: json['nombre_comercial']?.toString() ?? '',
        invoiceDate: DateTime.parse(json['invoice_date'].toString()),
        reminderDate: DateTime.parse(json['reminder_date'].toString()),
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        comment: json['comment']?.toString() ?? '',
      );
}
