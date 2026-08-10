import 'package:cosmeticos_hg_reportes/models/factura.dart';
import 'package:cosmeticos_hg_reportes/models/payment_reminder.dart';
import 'package:cosmeticos_hg_reportes/screens/payment_reminders_screen.dart';
import 'package:cosmeticos_hg_reportes/services/payment_reminders_repository.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeReminders implements PaymentRemindersDataSource {
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
  Future<void> save(
      {required String facturaId,
      required DateTime paymentDate,
      required bool active,
      required bool notifyThreeDays,
      required bool notifyOneDay}) async {}
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
              notificationStatusLoader: () async =>
                  AuthorizationStatus.notDetermined)));
      await tester.pumpAndSettle();
      expect(find.text('Recordatorios de pago'), findsOneWidget);
      expect(
          find.textContaining('No tienes pagos programados'), findsOneWidget);
    });
  }
}
