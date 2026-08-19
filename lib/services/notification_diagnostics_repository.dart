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

class OrganizationNotificationTestPreparation {
  const OrganizationNotificationTestPreparation({
    required this.organizationName,
    required this.eligibleDevices,
    required this.executionId,
  });

  final String organizationName;
  final int eligibleDevices;
  final String executionId;
}

class OrganizationNotificationTestResult {
  const OrganizationNotificationTestResult({
    required this.eligibleDevices,
    required this.successfulSends,
    required this.invalidTokens,
    required this.failures,
    required this.duplicatesOmitted,
    required this.organizationVerified,
    required this.businessDataModified,
  });

  final int eligibleDevices;
  final int successfulSends;
  final int invalidTokens;
  final int failures;
  final int duplicatesOmitted;
  final bool organizationVerified;
  final bool businessDataModified;
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

  Future<OrganizationNotificationTestPreparation>
      prepareOrganizationTest() async {
    final response = await _client.functions.invoke(
      'process-payment-reminders/organization-notification-test',
      body: const {'operation': 'prepare'},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return OrganizationNotificationTestPreparation(
      organizationName: data['organization_name'].toString(),
      eligibleDevices: (data['eligible_devices'] as num).toInt(),
      executionId: data['execution_id'].toString(),
    );
  }

  Future<OrganizationNotificationTestResult> sendOrganizationTest(
      String executionId) async {
    final response = await _client.functions.invoke(
      'process-payment-reminders/organization-notification-test',
      body: {'operation': 'send', 'execution_id': executionId},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return OrganizationNotificationTestResult(
      eligibleDevices: (data['eligible_devices'] as num).toInt(),
      successfulSends: (data['successful_sends'] as num).toInt(),
      invalidTokens: (data['invalid_tokens'] as num).toInt(),
      failures: (data['failures'] as num).toInt(),
      duplicatesOmitted: (data['duplicates_omitted'] as num).toInt(),
      organizationVerified: data['organization_verified'] == true,
      businessDataModified: data['business_data_modified'] == true,
    );
  }
}
