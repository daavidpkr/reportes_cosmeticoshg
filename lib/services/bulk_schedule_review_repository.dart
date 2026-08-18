import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bulk_schedule_review.dart';
import 'request_id.dart';

abstract interface class BulkScheduleReviewDataSource {
  Future<BulkScheduleReview> preview();
  Future<BulkScheduleReview> apply(BulkScheduleReview preview,
      {Set<String> authorizedExceptionRefs = const {}});
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
  Future<BulkScheduleReview> apply(BulkScheduleReview preview,
      {Set<String> authorizedExceptionRefs = const {}}) async {
    final tokens = {
      for (final item in preview.items)
        if (item.versionToken.isNotEmpty) item.reference: item.versionToken
    };
    final result = await _client
        .rpc('enterprise_apply_safe_bulk_invoice_rescheduling', params: {
      'p_request_id': newRequestId(),
      'p_preview_id': preview.previewId,
      'p_authorized_exception_refs': authorizedExceptionRefs.toList(),
      'p_row_version_tokens': tokens,
    });
    return BulkScheduleReview.fromJson(
        Map<String, dynamic>.from(result as Map));
  }
}
