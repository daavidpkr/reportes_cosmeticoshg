import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/payment_calendar_entry.dart';
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

class PaymentCalendarRepository
    implements PaymentCalendarDataSource, CalendarPaymentDataSource {
  PaymentCalendarRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

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
  Future<PaymentCalendarEntry> updateReminder({
    required PaymentCalendarEntry entry,
    required DateTime reminderDate,
    required String comment,
  }) async {
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
        .where((row) =>
            row['vendedor']?.toString().trim().toUpperCase() != 'ANULADA')
        .expand((row) => row['abonos'] as List? ?? const [])
        .fold<double>(0, (sum, value) => sum + (value as num).toDouble());
    final sale = (invoice['venta'] as num).toDouble();
    final canonicalBalance = (sale - paid).clamp(0, double.infinity);
    if ((canonicalBalance - expectedBalance).abs() > .005) {
      throw StateError('canonical payment balance was not confirmed');
    }
  }
}
