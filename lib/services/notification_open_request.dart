import 'dart:convert';

class NotificationOpenRequest {
  const NotificationOpenRequest({required this.localDate, this.facturaId});

  static const supportedTypes = {'recordatorio_pago', 'notification_test'};

  final DateTime localDate;
  final String? facturaId;

  static NotificationOpenRequest? fromData(Map<String, dynamic> data) {
    if (!supportedTypes.contains(data['type']?.toString().trim())) return null;
    final parsedDate =
        _parseCalendarDate(data['local_date']?.toString().trim() ?? '');
    final facturaId = data['factura_id']?.toString().trim();
    if (parsedDate == null && (facturaId == null || facturaId.isEmpty)) {
      return null;
    }
    if (facturaId != null && facturaId.length > 128) return null;
    final now = DateTime.now();
    return NotificationOpenRequest(
      localDate: parsedDate ?? DateTime(now.year, now.month, now.day),
      facturaId: facturaId,
    );
  }

  static DateTime? _parseCalendarDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final result = DateTime(year, month, day);
    return result.year == year && result.month == month && result.day == day
        ? result
        : null;
  }

  static NotificationOpenRequest? fromPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map
          ? fromData(Map<String, dynamic>.from(decoded))
          : null;
    } on FormatException {
      return null;
    }
  }
}

class NotificationOpeningGuard {
  NotificationOpeningGuard({this.maximumRemembered = 50});

  final int maximumRemembered;
  final Set<String> _processed = <String>{};

  bool markIfNew(String key) {
    if (key.isEmpty || _processed.contains(key)) return false;
    _processed.add(key);
    if (_processed.length > maximumRemembered) {
      _processed.remove(_processed.first);
    }
    return true;
  }
}
