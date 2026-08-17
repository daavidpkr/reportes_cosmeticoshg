import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import '../models/customer_history.dart';
import 'request_id.dart';

abstract interface class CustomerHistoryDataSource {
  Future<CustomerHistoryPage> load({
    required String customerId,
    required int offset,
    String status,
    String search,
    String sort,
  });
  Future<InvoiceTermRecalculation> previewRecalculation(String reference);
  Future<InvoiceTermRecalculation> reprogramInvoice(
      InvoiceTermRecalculation preview);
}

class CustomerHistoryRepository implements CustomerHistoryDataSource {
  CustomerHistoryRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<CustomerHistoryPage> load({
    required String customerId,
    required int offset,
    String status = 'all',
    String search = '',
    String sort = 'recent',
  }) async {
    const rpc = 'list_customer_invoice_history';
    try {
      final result = await _client.rpc(rpc, params: {
        'p_customer_id': customerId,
        'p_offset': offset,
        'p_limit': 25,
        'p_status': status,
        'p_search': search.trim(),
        'p_sort': sort,
      });
      try {
        return CustomerHistoryPage.fromJson(
            Map<String, dynamic>.from(result as Map));
      } catch (error) {
        debugPrint(
            'CustomerHistoryError type=${error.runtimeType} rpc=$rpc stage=serialization');
        rethrow;
      }
    } on PostgrestException catch (error) {
      debugPrint(
          'CustomerHistoryError type=PostgrestException rpc=$rpc code=${error.code} stage=rpc message=${_safeMessage(error.message)}');
      rethrow;
    }
  }

  @override
  Future<InvoiceTermRecalculation> previewRecalculation(
      String reference) async {
    final result = await _client.rpc('preview_invoice_term_recalculation',
        params: {'p_ref_fact': reference});
    final json = Map<String, dynamic>.from(result as Map);
    if (json['status'] == 'not_found' || json['status'] == 'not_eligible') {
      throw InvoiceReprogramException(json['reason']?.toString() ?? 'conflict');
    }
    return InvoiceTermRecalculation.fromJson(json);
  }

  @override
  Future<InvoiceTermRecalculation> reprogramInvoice(
      InvoiceTermRecalculation preview) async {
    final result =
        await _client.rpc('reprogram_invoice_with_current_term', params: {
      'p_request_id': newRequestId(),
      'p_ref_fact': preview.reference,
      'p_expected_term_days': preview.termDays,
      'p_expected_invoice_date':
          preview.invoiceDate.toIso8601String().split('T').first,
      'p_expected_current_date':
          preview.currentDate?.toIso8601String().split('T').first,
      'p_expected_reminder_updated_at':
          preview.reminderUpdatedAt?.toUtc().toIso8601String(),
    });
    return InvoiceTermRecalculation.fromJson(
        Map<String, dynamic>.from(result as Map));
  }

  String _safeMessage(String message) => message
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .substring(0, message.length > 160 ? 160 : message.length);
}
