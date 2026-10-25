import 'payment_reminder.dart';

class BillingCustomer {
  const BillingCustomer({
    required this.id,
    required this.name,
    required this.commercialName,
    required this.paymentTermDays,
    this.businessHours,
    this.address,
    this.phone,
    this.email,
    this.contactInvoiceDate,
    this.contactInvoiceReference,
    this.configurationActive = true,
  });
  final String id;
  final String name;
  final String commercialName;
  final int? paymentTermDays;
  final String? businessHours;
  final String? address, phone, email;
  final DateTime? contactInvoiceDate;
  final String? contactInvoiceReference;
  final bool configurationActive;
  bool get configured => paymentTermDays != null;

  BillingCustomer copyWith({
    int? paymentTermDays,
    String? businessHours,
    String? address,
    String? phone,
    String? email,
  }) =>
      BillingCustomer(
        id: id,
        name: name,
        commercialName: commercialName,
        paymentTermDays: paymentTermDays ?? this.paymentTermDays,
        businessHours: businessHours ?? this.businessHours,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        contactInvoiceDate: contactInvoiceDate,
        contactInvoiceReference: contactInvoiceReference,
        configurationActive: configurationActive,
      );

  factory BillingCustomer.fromJson(Map<String, dynamic> json) =>
      BillingCustomer(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        commercialName: json['commercial_name']?.toString() ?? '',
        paymentTermDays: (json['payment_term_days'] as num?)?.toInt(),
        businessHours: _optionalText(json['horario_atencion']),
        address: _optionalText(json['address']),
        phone: _optionalText(json['phone']),
        email: _optionalText(json['email']),
        contactInvoiceDate:
            DateTime.tryParse(json['contact_invoice_date']?.toString() ?? ''),
        contactInvoiceReference: _optionalText(json['contact_invoice_ref']),
        configurationActive: json['configuration_active'] != false,
      );
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
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
