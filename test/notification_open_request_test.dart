import 'package:cosmeticos_hg_reportes/services/notification_open_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationOpenRequest', () {
    test('acepta un recordatorio de pago con factura válida', () {
      final result = NotificationOpenRequest.fromData({
        'type': 'recordatorio_pago',
        'factura_id': 'FAC-123',
      });
      expect(result?.facturaId, 'FAC-123');
    });

    test('rechaza tipos, datos y factura_id inválidos', () {
      expect(NotificationOpenRequest.fromData(const {}), isNull);
      expect(
        NotificationOpenRequest.fromData(const {
          'type': 'otro',
          'factura_id': 'FAC-123',
        }),
        isNull,
      );
      expect(
        NotificationOpenRequest.fromData(const {
          'type': 'recordatorio_pago',
          'factura_id': '  ',
        }),
        isNull,
      );
      expect(NotificationOpenRequest.fromPayload('no es json'), isNull);
    });
  });

  test('abre el calendario en la fecha local indicada', () {
    final result = NotificationOpenRequest.fromData(const {
      'type': 'recordatorio_pago',
      'destination': 'payment_calendar',
      'local_date': '2026-08-21',
    });
    expect(result?.localDate, DateTime(2026, 8, 21));
    expect(result?.facturaId, isNull);
  });

  test('rechaza fechas imposibles sin desplazarlas de día', () {
    expect(
        NotificationOpenRequest.fromData(const {
          'type': 'notification_test',
          'local_date': '2026-02-30',
        }),
        isNull);
  });

  test('NotificationOpeningGuard evita procesar dos veces la apertura', () {
    final guard = NotificationOpeningGuard();
    expect(guard.markIfNew('mensaje-1'), isTrue);
    expect(guard.markIfNew('mensaje-1'), isFalse);
    expect(guard.markIfNew('mensaje-2'), isTrue);
  });
}
