import 'package:cosmeticos_hg_reportes/models/billing_customer.dart';
import 'package:cosmeticos_hg_reportes/screens/clientes_screen.dart';
import 'package:cosmeticos_hg_reportes/services/customer_terms_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCustomerTerms implements CustomerTermsDataSource {
  @override
  Future<InvoicePaymentPlan?> getInvoicePlan(String facturaId) async => null;
  @override
  Future<List<BillingCustomer>> listCustomers() async => const [
        BillingCustomer(
            id: '1',
            name: 'Cliente configurado',
            commercialName: 'Comercial Uno',
            paymentTermDays: 45),
        BillingCustomer(
            id: '2',
            name: 'Cliente pendiente',
            commercialName: '',
            paymentTermDays: null),
      ];
  @override
  Future<int> previewImpact(String customerId, int days) async => 0;
  @override
  Future<DateTime?> saveInvoiceException(String facturaId, int? days,
          {required bool confirmManualOverride}) async =>
      null;
  @override
  Future<int> savePaymentTerm(String customerId, int days,
          {required bool applyExisting}) async =>
      0;
}

void main() {
  testWidgets('muestra clientes configurados y pendientes', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClientesScreen(repository: FakeCustomerTerms()))));
    await tester.pumpAndSettle();
    expect(find.text('Cliente configurado'), findsOneWidget);
    expect(find.textContaining('45 días · Configurado'), findsOneWidget);
    expect(find.text('Cliente pendiente'), findsOneWidget);
    expect(
        find.textContaining('Plazo pendiente de configurar'), findsOneWidget);
  });
}
