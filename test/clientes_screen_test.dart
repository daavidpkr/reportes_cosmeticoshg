import 'package:cosmeticos_hg_reportes/models/billing_customer.dart';
import 'package:cosmeticos_hg_reportes/models/customer_history.dart';
import 'package:cosmeticos_hg_reportes/screens/clientes_screen.dart';
import 'package:cosmeticos_hg_reportes/services/customer_terms_repository.dart';
import 'package:cosmeticos_hg_reportes/services/customer_history_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCustomerTerms implements CustomerTermsDataSource {
  bool? lastApplyExisting;
  int previewed = 0;
  int deleted = 0;
  int scheduled = 0;
  bool failDelete = false;
  @override
  Future<void> deleteCustomer(BillingCustomer customer) async {
    if (failDelete) throw Exception('remote details');
    deleted++;
  }

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
  Future<int> previewImpact(String customerId, int days) async => previewed;
  @override
  Future<DateTime?> saveInvoiceException(String facturaId, int? days,
          {required bool confirmManualOverride}) async =>
      null;
  @override
  Future<int> savePaymentTerm(String customerId, int days,
      {required bool applyExisting}) async {
    lastApplyExisting = applyExisting;
    return previewed;
  }

  @override
  Future<CustomerSchedulingResult> schedulePending(
      BillingCustomer customer) async {
    scheduled++;
    return const CustomerSchedulingResult(
        eligibleCount: 2,
        createdCount: 2,
        skippedExistingCount: 1,
        skippedCount: 0);
  }
}

class FilterCustomerTerms extends FakeCustomerTerms {
  @override
  Future<List<BillingCustomer>> listCustomers() async => const [
        BillingCustomer(
            id: '1',
            name: 'N97 ANGELITA NOEMI SANCHEZ LLANOS',
            commercialName: 'Farmacia Esperanza',
            paymentTermDays: 30),
        BillingCustomer(
            id: '2',
            name: 'Cliente contado',
            commercialName: 'Comercial Cero',
            paymentTermDays: 0),
        BillingCustomer(
            id: '3',
            name: 'Cliente pendiente',
            commercialName: 'Farmacia Norte',
            paymentTermDays: null),
        BillingCustomer(
            id: '4',
            name: 'Cliente diez',
            commercialName: 'Tienda Sur',
            paymentTermDays: 10),
      ];
}

class FakeHistory implements CustomerHistoryDataSource {
  @override
  Future<CustomerHistoryPage> load(
          {required String customerId,
          required int offset,
          String status = 'all',
          String search = '',
          String sort = 'recent'}) async =>
      const CustomerHistoryPage(
          summary: CustomerHistorySummary(
              totalSales: 300,
              totalPaid: 150,
              balance: 150,
              totalInvoices: 3,
              paidInvoices: 1,
              pendingInvoices: 1,
              overdueInvoices: 1,
              cancelledInvoices: 1),
          invoices: [],
          filteredCount: 0);
}

void main() {
  testWidgets('tocar información abre historial y las acciones no lo abren',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ClientesScreen(
                repository: FakeCustomerTerms(),
                historyRepository: FakeHistory()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente configurado'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Historial del cliente'), findsOneWidget);
    expect(find.text('Total histórico'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar cliente').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Historial del cliente'), findsNothing);
    expect(find.text('Plazo habitual en días'), findsOneWidget);
  });

  testWidgets('busca por código, nombre y nombre comercial sin distinguir caso',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home:
            Scaffold(body: ClientesScreen(repository: FilterCustomerTerms()))));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('customer-search'));
    await tester.enterText(search, '  n97  ');
    await tester.pump();
    expect(find.text('N97 ANGELITA NOEMI SANCHEZ LLANOS'), findsOneWidget);
    expect(find.text('Cliente contado'), findsNothing);
    await tester.enterText(search, 'FARMACIA ESPERANZA');
    await tester.pump();
    expect(find.text('N97 ANGELITA NOEMI SANCHEZ LLANOS'), findsOneWidget);
    await tester.tap(find.byTooltip('Limpiar búsqueda'));
    await tester.pump();
    expect(find.text('Cliente contado'), findsOneWidget);
  });

  testWidgets(
      'genera, ordena y combina plazos reales distinguiendo cero y null',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home:
            Scaffold(body: ClientesScreen(repository: FilterCustomerTerms()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<Object?>));
    await tester.pumpAndSettle();
    expect(find.text('0 días'), findsWidgets);
    expect(find.text('10 días'), findsWidgets);
    expect(find.text('30 días'), findsWidgets);
    expect(find.text('Pendiente'), findsWidgets);
    expect(find.text('15 días'), findsNothing);
    await tester.tap(find.text('30 días').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('customer-search')), 'farmacia');
    await tester.pump();
    expect(find.text('N97 ANGELITA NOEMI SANCHEZ LLANOS'), findsOneWidget);
    expect(find.text('Cliente pendiente'), findsNothing);
  });

  testWidgets('explica resultados vacíos y limpia ambos filtros',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home:
            Scaffold(body: ClientesScreen(repository: FilterCustomerTerms()))));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('customer-search')), 'inexistente');
    await tester.pump();
    expect(find.text('No se encontraron clientes'), findsOneWidget);
    expect(find.textContaining('Prueba con otro nombre'), findsOneWidget);
    await tester.tap(find.text('Limpiar filtros').last);
    await tester.pump();
    expect(find.text('Cliente contado'), findsOneWidget);
  });

  testWidgets('muestra clientes configurados y pendientes', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClientesScreen(repository: FakeCustomerTerms()))));
    await tester.pumpAndSettle();
    expect(find.text('Cliente configurado'), findsOneWidget);
    expect(find.text('Nombre comercial'), findsNWidgets(2));
    expect(find.text('Comercial Uno'), findsOneWidget);
    expect(find.text('45 días'), findsOneWidget);
    expect(find.text('Cliente pendiente'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);
  });

  testWidgets('programa pendientes automáticamente al guardar días',
      (tester) async {
    final repository = FakeCustomerTerms()..previewed = 2;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClientesScreen(repository: repository))));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar cliente').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).last, '10');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(repository.lastApplyExisting, isTrue);
    expect(
        find.text('Plazo guardado y 2 facturas programadas.'), findsOneWidget);
  });

  testWidgets('muestra tres acciones y deshabilita programar pendiente',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClientesScreen(repository: FakeCustomerTerms()))));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Editar cliente'), findsNWidgets(2));
    expect(find.byTooltip('Eliminar cliente'), findsNWidgets(2));
    expect(find.byTooltip('Programar facturas pendientes'), findsOneWidget);
    expect(
        find.byTooltip('Configura primero los días de pago'), findsOneWidget);
    final scheduleButtons = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .where((button) =>
            button.icon is Icon &&
            (button.icon as Icon).icon == Icons.event_repeat_outlined);
    expect(scheduleButtons.where((button) => button.onPressed == null),
        hasLength(1));
  });

  testWidgets('confirma, programa una sola vez y muestra resultado',
      (tester) async {
    final repository = FakeCustomerTerms();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClientesScreen(repository: repository))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Programar facturas pendientes'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Programar facturas pendientes'), findsOneWidget);
    expect(find.textContaining('Los recordatorios existentes'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Programar'));
    await tester.pumpAndSettle();
    expect(repository.scheduled, 1);
    expect(find.text('Se programaron 2 facturas pendientes en el calendario.'),
        findsOneWidget);
  });

  testWidgets('elimina solo después de confirmar', (tester) async {
    final repository = FakeCustomerTerms();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClientesScreen(repository: repository))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eliminar cliente').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('facturas, abonos y recordatorios'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar cliente'));
    await tester.pumpAndSettle();
    expect(repository.deleted, 1);
    expect(find.textContaining('Sus facturas y recordatorios se conservaron'),
        findsOneWidget);
  });

  testWidgets('error remoto conserva el diálogo y no muestra éxito',
      (tester) async {
    final repository = FakeCustomerTerms()..failDelete = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClientesScreen(repository: repository))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eliminar cliente').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar cliente'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        find.text('No se pudo completar la operación. Inténtalo nuevamente.'),
        findsOneWidget);
    expect(find.textContaining('Sus facturas y recordatorios se conservaron'),
        findsNothing);
  });

  for (final size in <Size>[
    const Size(360, 800),
    const Size(390, 844),
    const Size(412, 915),
    const Size(768, 1024),
    const Size(1024, 768),
    const Size(1280, 720),
    const Size(1366, 768),
    const Size(1600, 900),
    const Size(1920, 1080),
  ]) {
    testWidgets(
        'tarjetas compactas sin overflow en ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home:
              Scaffold(body: ClientesScreen(repository: FakeCustomerTerms()))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final cards = find.byType(Card);
      expect(cards, findsNWidgets(2));
      final firstRect = tester.getRect(cards.first);
      expect(firstRect.left, greaterThanOrEqualTo(16));
      expect(firstRect.right, lessThanOrEqualTo(size.width - 16));
      expect(firstRect.height, lessThan(size.width < 620 ? 170 : 100));
      expect(find.byTooltip('Eliminar cliente'), findsNWidgets(2));
    });
  }
}
