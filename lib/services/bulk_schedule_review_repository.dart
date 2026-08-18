import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bulk_schedule_review.dart';
import 'request_id.dart';

abstract interface class BulkScheduleReviewDataSource {
  Future<BulkScheduleReview> preview();
  Future<BulkScheduleReview> apply(BulkScheduleReview preview);
}

class BulkScheduleReviewRepository implements BulkScheduleReviewDataSource {
  BulkScheduleReviewRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<BulkScheduleReview> preview() async =>
      BulkScheduleReview.fromJson(Map<String, dynamic>.from(await _client
          .rpc('enterprise_preview_bulk_invoice_rescheduling') as Map));

  @override
  Future<BulkScheduleReview> apply(BulkScheduleReview preview) async {
    final snapshot = {
      'items': preview.items
          .map((item) => {
                'ref_fact': item.reference,
                'classification': item.classification,
                'payment_term_days': item.termDays,
                'current_scheduled_date':
                    item.currentDate?.toIso8601String().split('T').first,
                'expected_scheduled_date':
                    item.expectedDate?.toIso8601String().split('T').first,
                'date_source': item.dateSource,
              })
          .toList()
    };
    final result = await _client.rpc(
        'enterprise_apply_safe_bulk_invoice_rescheduling',
        params: {'p_request_id': newRequestId(), 'p_preview': snapshot});
    return BulkScheduleReview.fromJson(
        Map<String, dynamic>.from(result as Map));
  }
}
