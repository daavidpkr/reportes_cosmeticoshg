import 'payment_reminder.dart';

class BillingCustomer {
  const BillingCustomer({
    required this.id,
    required this.name,
    required this.commercialName,
    required this.paymentTermDays,
  });
  final String id;
  final String name;
  final String commercialName;
  final int? paymentTermDays;
  bool get configured => paymentTermDays != null;

  factory BillingCustomer.fromJson(Map<String, dynamic> json) =>
      BillingCustomer(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        commercialName: json['commercial_name']?.toString() ?? '',
        paymentTermDays: (json['payment_term_days'] as num?)?.toInt(),
      );
}

class InvoicePaymentPlan {
  const InvoicePaymentPlan({
    required this.invoiceDate,
    required this.customerTermDays,
    required this.exceptionalTermDays,
    required this.currentPaymentDate,
    required this.manualSchedule,
  });
  final DateTime? invoiceDate;
  final int? customerTermDays;
  final int? exceptionalTermDays;
  final DateTime? currentPaymentDate;
  final bool manualSchedule;
  int? get applicableDays => exceptionalTermDays ?? customerTermDays;
  DateTime? get calculatedDate => invoiceDate == null || applicableDays == null
      ? null
      : calculatePaymentDate(invoiceDate!, applicableDays!);
}

DateTime? parseInvoiceDate(String value) {
  final match =
      RegExp(r'^(\d{1,4})[-/](\d{1,2})[-/](\d{1,4})').firstMatch(value.trim());
  if (match == null) return null;
  final first = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final last = int.tryParse(match.group(3)!);
  if (first == null || month == null || last == null) return null;
  final year = match.group(1)!.length == 4 ? first : last;
  final day = match.group(1)!.length == 4 ? last : first;
  final result = DateTime(year, month, day);
  return result.year == year && result.month == month && result.day == day
      ? result
      : null;
}

DateTime calculatePaymentDate(DateTime invoiceDate, int termDays) {
  if (termDays < 0) throw ArgumentError.value(termDays, 'termDays');
  return effectiveBusinessDate(invoiceDate.add(Duration(days: termDays)));
}

int? parsePaymentTerm(String value) {
  if (!RegExp(r'^\d+$').hasMatch(value.trim())) return null;
  return int.tryParse(value.trim());
}
