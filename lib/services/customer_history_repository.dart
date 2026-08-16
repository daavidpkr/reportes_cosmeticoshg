import 'package:supabase_flutter/supabase_flutter.dart';

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
    final result = await _client.rpc('list_customer_invoice_history', params: {
      'p_customer_id': customerId,
      'p_offset': offset,
      'p_limit': 25,
      'p_status': status,
      'p_search': search.trim(),
      'p_sort': sort,
    });
    return CustomerHistoryPage.fromJson(
        Map<String, dynamic>.from(result as Map));
  }
}
