import 'package:cosmeticos_hg_reportes/models/factura.dart';
import 'package:cosmeticos_hg_reportes/models/payment_reminder.dart';
import 'package:cosmeticos_hg_reportes/screens/payment_reminders_screen.dart';
import 'package:cosmeticos_hg_reportes/services/payment_reminders_repository.dart';
import 'package:cosmeticos_hg_reportes/services/notification_diagnostics_repository.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeReminders implements PaymentRemindersDataSource {
  @override
  Future<FollowupResult> addFollowup(
          {required String reminderId,
          required String requestId,
          String? comment,
          DateTime? requestedPaymentDate}) async =>
      FollowupResult(
          actionType: requestedPaymentDate == null ? 'comment' : 'reschedule',
          effectivePaymentDate: requestedPaymentDate ?? DateTime(2026, 8, 10));
  @override
  Future<void> delete(String id) async {}
  @override
  Future<PaymentReminder?> findForInvoice(String facturaId) async => null;
  @override
  Future<Factura?> findInvoice(String facturaId) async => null;
  @override
  Future<List<PaymentReminder>> list() async => [];
  @override
  Future<List<Factura>> listInvoices() async => [];
  @override
  Future<List<PaymentFollowup>> listFollowups(String reminderId) async => [];
  @override
  Future<void> save(
      {required String facturaId,
      required DateTime paymentDate,
      required bool active,
      required bool notifyThreeDays,
      required bool notifyOneDay}) async {}
}

class FakeDiagnostics implements NotificationDiagnosticsDataSource {
  int previews = 0;
  int sends = 0;

  @override
  Future<NotificationTestPreview> previewAllMyDevices() async {
    previews++;
    return const NotificationTestPreview(
        eligibleDevices: 2,
        inactiveDevices: 1,
        duplicatesOmitted: 1,
        executionId: '00000000-0000-0000-0000-000000000001');
  }

  @override
  Future<NotificationTestResult> sendToAllMyDevices(String executionId) async {
    sends++;
    return const NotificationTestResult(
        eligibleDevices: 2,
        successfulSends: 2,
        invalidTokens: 0,
        failures: 0,
        duplicatesOmitted: 1);
  }
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('la interfaz funciona en ${mode.name}', (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: mode,
          home: PaymentRemindersScreen(
              repository: FakeReminders(),
              notificationDiagnostics: FakeDiagnostics(),
              notificationStatusLoader: () async =>
                  AuthorizationStatus.notDetermined)));
      await tester.pumpAndSettle();
      expect(find.text('Recordatorios de pago'), findsOneWidget);
      expect(
          find.textContaining('No tienes pagos programados'), findsOneWidget);
    });
  }

  testWidgets('la vista previa requiere confirmación y cancelar no envía',
      (tester) async {
    final diagnostics = FakeDiagnostics();
    await tester.pumpWidget(MaterialApp(
        home: PaymentRemindersScreen(
            repository: FakeReminders(),
            notificationDiagnostics: diagnostics,
            notificationStatusLoader: () async =>
                AuthorizationStatus.authorized)));
    await tester.pumpAndSettle();
    await tester
        .tap(find.text('Probar notificaciones en todos mis dispositivos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Dispositivos Android elegibles: 2'), findsOneWidget);
    expect(find.text('Dispositivos inactivos: 1'), findsOneWidget);
    expect(find.text('Tokens duplicados omitidos: 1'), findsOneWidget);
    expect(find.text('Confirmar y enviar'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(diagnostics.previews, 1);
    expect(diagnostics.sends, 0);
    expect(find.text('Resultado de la prueba'), findsNothing);
  });

  testWidgets('confirmar realiza un solo envío', (tester) async {
    final diagnostics = FakeDiagnostics();
    await tester.pumpWidget(MaterialApp(
        home: PaymentRemindersScreen(
      repository: FakeReminders(),
      notificationDiagnostics: diagnostics,
      notificationStatusLoader: () async => AuthorizationStatus.authorized,
    )));
    await tester.pumpAndSettle();
    await tester
        .tap(find.text('Probar notificaciones en todos mis dispositivos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Confirmar y enviar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(diagnostics.sends, 1);
    expect(find.text('Resultado de la prueba'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
  });
}
