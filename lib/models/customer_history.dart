class CustomerHistorySummary {
  const CustomerHistorySummary({
    required this.totalSales,
    required this.totalPaid,
    required this.balance,
    required this.totalInvoices,
    required this.paidInvoices,
    required this.pendingInvoices,
    required this.overdueInvoices,
    required this.cancelledInvoices,
    this.lastPurchase,
    this.nextPayment,
  });
  final double totalSales, totalPaid, balance;
  final int totalInvoices, paidInvoices, pendingInvoices, overdueInvoices;
  final int cancelledInvoices;
  final DateTime? lastPurchase, nextPayment;

  factory CustomerHistorySummary.fromJson(Map<String, dynamic> json) =>
      CustomerHistorySummary(
        totalSales: (json['total_sales'] as num?)?.toDouble() ?? 0,
        totalPaid: (json['total_paid'] as num?)?.toDouble() ?? 0,
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        totalInvoices: (json['total_invoices'] as num?)?.toInt() ?? 0,
        paidInvoices: (json['paid_invoices'] as num?)?.toInt() ?? 0,
        pendingInvoices: (json['pending_invoices'] as num?)?.toInt() ?? 0,
        overdueInvoices: (json['overdue_invoices'] as num?)?.toInt() ?? 0,
        cancelledInvoices: (json['cancelled_invoices'] as num?)?.toInt() ?? 0,
        lastPurchase: _date(json['last_purchase']),
        nextPayment: _date(json['next_payment']),
      );
}

class CustomerHistoryInvoice {
  const CustomerHistoryInvoice({
    required this.reference,
    required this.invoiceNumber,
    required this.date,
    required this.seller,
    required this.reportMonth,
    required this.sale,
    required this.paid,
    required this.balance,
    required this.cancelled,
    required this.overdue,
    required this.payments,
    this.reminderDate,
    this.calendarComment = '',
    this.scheduleSource,
  });
  final String reference, invoiceNumber, seller, reportMonth, calendarComment;
  final DateTime date;
  final DateTime? reminderDate;
  final String? scheduleSource;
  final double sale, paid, balance;
  final bool cancelled, overdue;
  final List<CustomerHistoryPayment> payments;
  bool get isPaid => !cancelled && balance <= .005;
  String get status => cancelled
      ? 'Anulada'
      : overdue
          ? 'Vencida'
          : isPaid
              ? 'Pagada'
              : 'Pendiente';

  factory CustomerHistoryInvoice.fromJson(Map<String, dynamic> json) =>
      CustomerHistoryInvoice(
        reference: json['reference']?.toString() ?? '',
        invoiceNumber: json['invoice_number']?.toString() ?? '',
        date: DateTime.parse(json['invoice_date'].toString()),
        seller: json['seller']?.toString() ?? '',
        reportMonth: json['report_month']?.toString() ?? '',
        sale: (json['sale'] as num?)?.toDouble() ?? 0,
        paid: (json['paid'] as num?)?.toDouble() ?? 0,
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        cancelled: json['cancelled'] == true,
        overdue: json['overdue'] == true,
        reminderDate: _date(json['reminder_date']),
        calendarComment: json['calendar_comment']?.toString() ?? '',
        scheduleSource: json['schedule_source']?.toString(),
        payments: (json['payments'] as List? ?? const [])
            .map((item) => CustomerHistoryPayment.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}

class InvoiceTermRecalculation {
  const InvoiceTermRecalculation({
    required this.reference,
    required this.invoiceDate,
    required this.termDays,
    required this.newDate,
    required this.manualSchedule,
    required this.alreadyCurrent,
    this.currentDate,
    this.confirmationRequired = false,
    this.updatedCount = 0,
    this.status = 'confirmation_required',
    this.reason,
    this.reminderUpdatedAt,
  });
  final String reference;
  final DateTime invoiceDate, newDate;
  final DateTime? currentDate;
  final int termDays, updatedCount;
  final bool manualSchedule, alreadyCurrent, confirmationRequired;
  final String status;
  final String? reason;
  final DateTime? reminderUpdatedAt;

  factory InvoiceTermRecalculation.fromJson(Map<String, dynamic> json) =>
      InvoiceTermRecalculation(
        reference: json['reference'].toString(),
        invoiceDate: DateTime.parse(json['invoice_date'].toString()),
        termDays: (json['term_days'] as num).toInt(),
        currentDate: _date(json['current_date']),
        newDate: DateTime.parse(json['new_date'].toString()),
        manualSchedule: json['manual_schedule'] == true,
        alreadyCurrent: json['already_current'] == true,
        confirmationRequired: json['confirmation_required'] == true,
        updatedCount: (json['updated_count'] as num?)?.toInt() ?? 0,
        status: json['status']?.toString() ??
            (json['already_current'] == true
                ? 'already_current'
                : 'confirmation_required'),
        reason: json['reason']?.toString(),
        reminderUpdatedAt: _date(json['reminder_updated_at']),
      );
}

class InvoiceReprogramException implements Exception {
  const InvoiceReprogramException(this.reason);
  final String reason;
}

class CustomerHistoryPayment {
  const CustomerHistoryPayment(
      {required this.amount, this.receiptNumber, this.comment = ''});
  final double amount;
  final int? receiptNumber;
  final String comment;
  factory CustomerHistoryPayment.fromJson(Map<String, dynamic> json) =>
      CustomerHistoryPayment(
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        receiptNumber: (json['receipt'] as num?)?.toInt(),
        comment: json['comment']?.toString() ?? '',
      );
}

class CustomerHistoryPage {
  const CustomerHistoryPage(
      {required this.summary,
      required this.invoices,
      required this.filteredCount});
  final CustomerHistorySummary summary;
  final List<CustomerHistoryInvoice> invoices;
  final int filteredCount;
  factory CustomerHistoryPage.fromJson(Map<String, dynamic> json) =>
      CustomerHistoryPage(
        summary: CustomerHistorySummary.fromJson(
            Map<String, dynamic>.from(json['summary'] as Map? ?? const {})),
        invoices: (json['invoices'] as List? ?? const [])
            .map((item) => CustomerHistoryInvoice.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
        filteredCount: (json['filtered_count'] as num?)?.toInt() ?? 0,
      );
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());
