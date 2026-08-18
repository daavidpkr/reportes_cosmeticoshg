import 'package:supabase_flutter/supabase_flutter.dart';

import 'request_id.dart';

class NotificationDeviceSummary {
  const NotificationDeviceSummary({
    required this.id,
    required this.platform,
    required this.lastSeenAt,
    required this.fingerprint,
  });

  final String id;
  final String platform;
  final DateTime lastSeenAt;
  final String fingerprint;
}

class NotificationDiagnosticsRepository {
  NotificationDiagnosticsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<NotificationDeviceSummary>> listOwnDevices() async {
    final rows = await _client.rpc('list_my_notification_devices') as List;
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .map((row) => NotificationDeviceSummary(
              id: row['device_id'].toString(),
              platform: row['platform'].toString(),
              lastSeenAt: DateTime.parse(row['last_seen_at'].toString()),
              fingerprint: row['fingerprint'].toString(),
            ))
        .toList();
  }

  Future<String> sendTest(String deviceId) async {
    final response = await _client.functions.invoke(
      'process-payment-reminders/notification-test',
      body: {'device_id': deviceId, 'request_id': newRequestId()},
    );
    final data = response.data;
    if (data is Map && data['status'] != null) return data['status'].toString();
    return 'failed';
  }
}
