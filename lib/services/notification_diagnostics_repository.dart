import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationTestPreview {
  const NotificationTestPreview(
      {required this.eligibleDevices,
      required this.inactiveDevices,
      required this.duplicatesOmitted,
      required this.executionId});
  final int eligibleDevices;
  final int inactiveDevices;
  final int duplicatesOmitted;
  final String executionId;
}

class NotificationTestResult {
  const NotificationTestResult(
      {required this.eligibleDevices,
      required this.successfulSends,
      required this.invalidTokens,
      required this.failures,
      required this.duplicatesOmitted});
  final int eligibleDevices;
  final int successfulSends;
  final int invalidTokens;
  final int failures;
  final int duplicatesOmitted;
}

abstract interface class NotificationDiagnosticsDataSource {
  Future<NotificationTestPreview> previewAllMyDevices();
  Future<NotificationTestResult> sendToAllMyDevices(String executionId);
}

class NotificationDiagnosticsRepository
    implements NotificationDiagnosticsDataSource {
  NotificationDiagnosticsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    // functions.invoke adjunta automáticamente el access_token vigente.
    if (_client.auth.currentSession == null) {
      throw const AuthException('No hay una sesión autenticada vigente.');
    }
    final response = await _client.functions.invoke(
      'process-payment-reminders/user-notification-test',
      body: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  Future<NotificationTestPreview> previewAllMyDevices() async {
    final data = await _invoke(const {'operation': 'preview'});
    return NotificationTestPreview(
      eligibleDevices: (data['eligible_devices'] as num).toInt(),
      inactiveDevices: (data['inactive_devices'] as num).toInt(),
      duplicatesOmitted: (data['duplicates_omitted'] as num).toInt(),
      executionId: data['execution_id'].toString(),
    );
  }

  @override
  Future<NotificationTestResult> sendToAllMyDevices(String executionId) async {
    final data =
        await _invoke({'operation': 'send', 'execution_id': executionId});
    return NotificationTestResult(
      eligibleDevices: (data['eligible_devices'] as num).toInt(),
      successfulSends: (data['successful_sends'] as num).toInt(),
      invalidTokens: (data['invalid_tokens'] as num).toInt(),
      failures: (data['failures'] as num).toInt(),
      duplicatesOmitted: (data['duplicates_omitted'] as num).toInt(),
    );
  }
}
