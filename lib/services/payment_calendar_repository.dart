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

class PaymentCalendarRepository implements PaymentCalendarDataSource {
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
}
