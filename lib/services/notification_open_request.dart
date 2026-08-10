import 'dart:convert';

class NotificationOpenRequest {
  const NotificationOpenRequest({required this.facturaId});

  static const supportedType = 'recordatorio_pago';

  final String facturaId;

  static NotificationOpenRequest? fromData(Map<String, dynamic> data) {
    if (data['type']?.toString().trim() != supportedType) return null;
    final facturaId = data['factura_id']?.toString().trim() ?? '';
    if (facturaId.isEmpty || facturaId.length > 128) return null;
    return NotificationOpenRequest(facturaId: facturaId);
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
