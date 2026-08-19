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
  FakeDiagnostics({this.admin = false});
  final bool admin;

  @override
  Future<bool> isOrganizationAdmin() async => admin;
  @override
  Future<List<NotificationDeviceSummary>> listOwnDevices() async => [];
  @override
  Future<String> sendTest(String deviceId) async => 'sent';
  @override
  Future<OrganizationNotificationTestPreparation>
      prepareOrganizationTest() async =>
          const OrganizationNotificationTestPreparation(
              organizationName: 'Cosméticos HG',
              eligibleDevices: 2,
              executionId: '00000000-0000-0000-0000-000000000001');
  @override
  Future<OrganizationNotificationTestResult> sendOrganizationTest(
          String executionId) async =>
      const OrganizationNotificationTestResult(
          eligibleDevices: 2,
          successfulSends: 2,
          invalidTokens: 0,
          failures: 0,
          duplicatesOmitted: 0,
          organizationVerified: true,
          businessDataModified: false);
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

  testWidgets('la prueba organizacional solo aparece para administradores',
      (tester) async {
    Future<void> pump(bool admin) async {
      await tester.pumpWidget(MaterialApp(
          home: PaymentRemindersScreen(
              key: ValueKey(admin),
              repository: FakeReminders(),
              notificationDiagnostics: FakeDiagnostics(admin: admin),
              notificationStatusLoader: () async =>
                  AuthorizationStatus.authorized)));
      await tester.pumpAndSettle();
    }

    await pump(false);
    expect(find.text('Prueba organizacional'), findsNothing);
    await pump(true);
    expect(find.text('Prueba organizacional'), findsOneWidget);
  });

  testWidgets('la vista previa requiere confirmación antes de enviar',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: PaymentRemindersScreen(
            repository: FakeReminders(),
            notificationDiagnostics: FakeDiagnostics(admin: true),
            notificationStatusLoader: () async =>
                AuthorizationStatus.authorized)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prueba organizacional'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Cosméticos HG'), findsOneWidget);
    expect(find.text('Dispositivos elegibles: 2'), findsOneWidget);
    expect(find.text('Confirmar y enviar'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Resultado de la prueba'), findsNothing);
  });
}
