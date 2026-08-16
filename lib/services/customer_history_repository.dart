import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import '../models/customer_history.dart';

abstract interface class CustomerHistoryDataSource {
  Future<CustomerHistoryPage> load({
    required String customerId,
    required int offset,
    String status,
    String search,
    String sort,
  });
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

  String _safeMessage(String message) => message
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .substring(0, message.length > 160 ? 160 : message.length);
}
