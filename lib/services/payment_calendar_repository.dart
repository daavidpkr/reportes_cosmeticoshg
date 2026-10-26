import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/payment_calendar_entry.dart';
import '../models/billing_customer.dart';
import '../models/fila_venta.dart';
import 'request_id.dart';

abstract interface class PaymentCalendarDataSource {
  Future<List<PaymentCalendarEntry>> listMonth(DateTime month);
  Future<PaymentCalendarEntry> updateReminder({
    required PaymentCalendarEntry entry,
    required DateTime reminderDate,
    required String comment,
  });
}

abstract interface class CalendarPaymentDataSource {
  Future<double> recordPayment({
    required PaymentCalendarEntry entry,
    required double amount,
    String comment,
    int? receiptNumber,
    bool payInFull,
  });
}

abstract interface class CalendarCustomerDataSource {
  Future<BillingCustomer?> resolveCustomer(String facturaId);
}

abstract interface class CalendarInvoiceSchedulingDataSource {
  Future<List<SchedulableInvoice>> searchSchedulableInvoices(String query);
  Future<PaymentCalendarEntry> scheduleInvoice({
    required String facturaId,
    required DateTime date,
    String comment = '',
  });
}

class PaymentCalendarRepository
    implements
        PaymentCalendarDataSource,
        CalendarPaymentDataSource,
        CalendarCustomerDataSource,
        CalendarInvoiceSchedulingDataSource {
  PaymentCalendarRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<BillingCustomer?> resolveCustomer(String facturaId) async {
    final row = await _client
        .from('invoice_payment_terms')
        .select(
            'customer_id,billing_customers(id,name,commercial_name,payment_term_days,horario_atencion,configuration_active)')
        .eq('factura_id', facturaId)
        .maybeSingle();
    final customer = row?['billing_customers'];
    return customer is Map
        ? BillingCustomer.fromJson(Map<String, dynamic>.from(customer))
        : null;
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _ensureInvoiceMutable(String facturaId) async {
    final rows = await _client
        .from('reportes_ventas')
        .select('vendedor')
        .eq('ref_fact', facturaId.trim());
    if (List<Map<String, dynamic>>.from(rows)
        .any((row) => esVendedorAnulado(row['vendedor']?.toString() ?? ''))) {
      throw StateError('Factura anulada: las acciones están bloqueadas');
    }
  }

  @override
  Future<List<PaymentCalendarEntry>> listMonth(DateTime month) async {
    final rows = await _client.rpc('list_pending_payment_calendar', params: {
      'p_month': _date(DateTime(month.year, month.month)),
    });
    return (rows as List)
        .map(
            (row) => PaymentCalendarEntry.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<SchedulableInvoice>> searchSchedulableInvoices(
      String query) async {
    final rows = await _client.rpc('search_schedulable_invoices', params: {
      'p_search': query.trim(),
      'p_limit': 30,
    });
    return (rows as List)
        .map((row) => SchedulableInvoice.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<PaymentCalendarEntry> scheduleInvoice({
    required String facturaId,
    required DateTime date,
    String comment = '',
  }) async {
    await _ensureInvoiceMutable(facturaId);
    final rows = await _client.rpc('schedule_invoice_on_calendar', params: {
      'p_request_id': newRequestId(),
      'p_factura_id': facturaId.trim(),
      'p_requested_payment_date': _date(date),
      'p_comment': comment.trim(),
    });
    return PaymentCalendarEntry.fromJson(
        (rows as List).single as Map<String, dynamic>);
  }

  @override
  Future<PaymentCalendarEntry> updateReminder({
    required PaymentCalendarEntry entry,
    required DateTime reminderDate,
    required String comment,
  }) async {
    await _ensureInvoiceMutable(entry.facturaId);
    final rows = await _client.rpc('update_payment_calendar_reminder', params: {
      'p_request_id': newRequestId(),
      'p_reminder_id': entry.reminderId,
      'p_requested_payment_date': _date(reminderDate),
      'p_comment': comment.trim(),
    });
    final row = (rows as List).single as Map<String, dynamic>;
    return entry.copyWith(
      reminderDate: DateTime.parse(row['effective_payment_date'].toString()),
      comment: row['comment']?.toString() ?? '',
    );
  }

  @override
  Future<double> recordPayment({
    required PaymentCalendarEntry entry,
    required double amount,
    String comment = '',
    int? receiptNumber,
    bool payInFull = false,
  }) async {
    await _ensureInvoiceMutable(entry.facturaId);
    final rows = await _client.rpc('record_calendar_payment', params: {
      'p_request_id': newRequestId(),
      'p_reminder_id': entry.reminderId,
      'p_amount': amount,
      'p_comment': comment.trim(),
      'p_receipt_number': receiptNumber,
      'p_pay_in_full': payInFull,
    });
    final row = (rows as List).single as Map<String, dynamic>;
    final remaining = (row['remaining_balance'] as num).toDouble();
    await _confirmCanonicalPayment(entry, remaining);
    return remaining;
  }

  Future<void> _confirmCanonicalPayment(
      PaymentCalendarEntry entry, double expectedBalance) async {
    final invoice = await _client
        .from('facturas_maestras')
        .select('ref_fact,nro_fact,venta')
        .eq('ref_fact', entry.facturaId)
        .single();
    final rows = await _client
        .from('reportes_ventas')
        .select('ref_fact,mes_reporte,vendedor,abonos')
        .eq('ref_fact', entry.facturaId);
    final reportRows = List<Map<String, dynamic>>.from(rows);
    if (invoice['ref_fact']?.toString() != entry.facturaId ||
        reportRows.isEmpty) {
      throw StateError('canonical invoice row was not confirmed');
    }
    final paid = reportRows
        .where((row) => !esVendedorAnulado(row['vendedor']?.toString() ?? ''))
        .expand((row) => row['abonos'] as List? ?? const [])
        .fold<double>(0, (sum, value) => sum + (value as num).toDouble());
    final sale = (invoice['venta'] as num).toDouble();
    final canonicalBalance = (sale - paid).clamp(0, double.infinity);
    if ((canonicalBalance - expectedBalance).abs() > .005) {
      throw StateError('canonical payment balance was not confirmed');
    }
  }
}
