import 'package:cosmeticos_hg_reportes/models/billing_customer.dart';
import 'package:cosmeticos_hg_reportes/models/bulk_schedule_review.dart';
import 'package:cosmeticos_hg_reportes/models/customer_history.dart';
import 'package:cosmeticos_hg_reportes/screens/clientes_screen.dart';
import 'package:cosmeticos_hg_reportes/screens/customer_history_screen.dart';
import 'package:cosmeticos_hg_reportes/services/customer_terms_repository.dart';
import 'package:cosmeticos_hg_reportes/services/bulk_schedule_review_repository.dart';
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

class FakeBulkReview implements BulkScheduleReviewDataSource {
  int previews = 0, applies = 0;
  Set<String> authorized = {};
  BulkScheduleReview get value =>
      BulkScheduleReview(previewId: 'preview-token', toleranceDays: 7, counts: {
        'total_reviewed': 4,
        'already_correct': 1,
        'safe_to_update': 1,
        'missing_reminders': 0,
        'manual_review': 2,
        'missing_payment_term': 0,
        'updated': 1,
        'created': 0,
        'changed_since_preview': 0,
        'errors': 0,
        'zero_term_customers': 2,
        'zero_term_invoices': 2,
        'authorized_updated': authorized.length,
        'unauthorized_exceptions': 2 - authorized.length,
      }, items: [
        BulkScheduleItem(
            customerId: '1',
            customer: 'Cliente configurado',
            commercialName: 'Comercial Uno',
            reference: '000000601',
            invoiceDate: DateTime(2026, 8, 1),
            termDays: 30,
            currentDate: DateTime(2026, 9, 2),
            expectedDate: DateTime(2026, 8, 31),
            differenceDays: 2,
            dateSource: 'customer_term',
            versionToken: 'safe-token',
            classification: 'safe_to_update',
            reason: 'within_tolerance'),
        BulkScheduleItem(
            customerId: '1',
            customer: 'Cliente configurado',
            commercialName: 'Comercial Uno',
            reference: '000000608',
            invoiceDate: DateTime(2026, 7, 7),
            termDays: 60,
            currentDate: DateTime(2026, 8, 6),
            expectedDate: DateTime(2026, 9, 7),
            differenceDays: 32,
            dateSource: 'customer_term',
            versionToken: 'exception-token',
            balance: 356.35,
            classification: 'manual_review',
            reason: 'outside_tolerance'),
        BulkScheduleItem(
            customerId: '1',
            customer: 'Cliente configurado',
            commercialName: 'Comercial Uno',
            reference: '000000665',
            invoiceDate: DateTime(2026, 7, 1),
            termDays: 45,
            currentDate: DateTime(2026, 8, 20),
            expectedDate: DateTime(2026, 8, 17),
            differenceDays: 3,
            dateSource: 'manual',
            versionToken: 'manual-token',
            classification: 'manual_review',
            reason: 'manual_date'),
      ]);
  @override
  Future<BulkScheduleReview> preview() async {
    previews++;
    return value;
  }

  @override
  Future<BulkScheduleReview> apply(BulkScheduleReview preview,
      {Set<String> authorizedExceptionRefs = const {}}) async {
    applies++;
    authorized = authorizedExceptionRefs;
    return value;
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
  InvoiceTermRecalculation? preview;
  int reprogrammed = 0;

  @override
  Future<InvoiceTermRecalculation> previewRecalculation(
          String reference) async =>
      preview ??
      InvoiceTermRecalculation(
          reference: reference,
          invoiceDate: DateTime(2026, 7, 3),
          termDays: 45,
          currentDate: DateTime(2026, 9, 1),
          newDate: DateTime(2026, 8, 17),
          manualSchedule: false,
          alreadyCurrent: false);

  @override
  Future<InvoiceTermRecalculation> reprogramInvoice(
      InvoiceTermRecalculation preview) async {
    reprogrammed++;
    return InvoiceTermRecalculation(
        reference: preview.reference,
        invoiceDate: preview.invoiceDate,
        termDays: preview.termDays,
        currentDate: preview.currentDate,
        newDate: preview.newDate,
        manualSchedule: preview.manualSchedule,
        alreadyCurrent: false,
        updatedCount: 1,
        status: 'updated');
  }

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

class FlakyHistory extends FakeHistory {
  int attempts = 0;
  @override
  Future<CustomerHistoryPage> load(
      {required String customerId,
      required int offset,
      String status = 'all',
      String search = '',
      String sort = 'recent'}) async {
    attempts++;
    if (attempts == 1) throw Exception('remote error');
    return super.load(
        customerId: customerId,
        offset: offset,
        status: status,
        search: search,
        sort: sort);
  }
}

class RosaHistory extends FakeHistory {
  int loads = 0;
  bool saved = false;

  @override
  Future<InvoiceTermRecalculation> reprogramInvoice(
      InvoiceTermRecalculation preview) async {
    final result = await super.reprogramInvoice(preview);
    saved = true;
    return result;
  }

  @override
  Future<CustomerHistoryPage> load(
      {required String customerId,
      required int offset,
      String status = 'all',
      String search = '',
      String sort = 'recent'}) async {
    loads++;
    return CustomerHistoryPage(
        summary: const CustomerHistorySummary(
            totalSales: 21.86,
            totalPaid: 0,
            balance: 21.86,
            totalInvoices: 2,
            paidInvoices: 0,
            pendingInvoices: 2,
            overdueInvoices: 0,
            cancelledInvoices: 0),
        invoices: [
          CustomerHistoryInvoice(
              reference: '000000601',
              invoiceNumber: '601',
              date: DateTime(2026, 7, 3),
              seller: 'Vendedor',
              reportMonth: 'JULIO 2026',
              sale: 21.86,
              paid: 0,
              balance: 21.86,
              cancelled: false,
              overdue: false,
              reminderDate:
                  saved ? DateTime(2026, 8, 17) : DateTime(2026, 9, 1),
              calendarComment: 'Conservar',
              payments: const []),
          CustomerHistoryInvoice(
              reference: '000000664',
              invoiceNumber: '664',
              date: DateTime(2026, 7, 29),
              seller: 'Vendedor',
              reportMonth: 'JULIO 2026',
              sale: 10,
              paid: 0,
              balance: 10,
              cancelled: false,
              overdue: false,
              payments: const []),
        ],
        filteredCount: 2);
  }
}

void main() {
  testWidgets('revisa y confirma solo programaciones masivas seguras',
      (tester) async {
    final bulk = FakeBulkReview();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ClientesScreen(
                repository: FakeCustomerTerms(),
                historyRepository: FakeHistory(),
                bulkReviewRepository: bulk))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-bulk-schedules')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-bulk-schedules')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Revisión de programaciones'), findsOneWidget);
    expect(find.text('Listas para actualizar: 1'), findsOneWidget);
    expect(find.text('Requieren revisión manual: 2'), findsOneWidget);
    expect(find.text('Factura 000000608'), findsOneWidget);
    expect(find.text('Factura 000000665'), findsOneWidget);
    await tester.tap(
        find.widgetWithText(FilledButton, 'Actualizar seguras y autorizadas'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(bulk.applies, 1);
    expect(bulk.previews, 2); // preview plus authoritative second read
    expect(find.text('Actualización completada'), findsOneWidget);
    expect(find.text('Actualizadas autom\u00e1ticamente: 1'), findsOneWidget);
    expect(find.text('Factura 000000608'), findsOneWidget);
  });

  testWidgets('autoriza expresamente la excepciÃ³n 608 de 32 dÃ­as',
      (tester) async {
    final bulk = FakeBulkReview();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ClientesScreen(
                repository: FakeCustomerTerms(),
                historyRepository: FakeHistory(),
                bulkReviewRepository: bulk))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review-bulk-schedules')));
    await tester.pump(const Duration(milliseconds: 300));
    final exception =
        find.widgetWithText(CheckboxListTile, 'Factura 000000608');
    expect(exception, findsOneWidget);
    await tester.scrollUntilVisible(exception, 300,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(exception);
    await tester.pump();
    final update =
        find.widgetWithText(FilledButton, 'Actualizar seguras y autorizadas');
    await tester.ensureVisible(update);
    await tester.tap(update);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        find.text('Confirmar reprogramaciones excepcionales'), findsOneWidget);
    await tester
        .tap(find.widgetWithText(FilledButton, 'Confirmar y actualizar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(bulk.authorized, {'000000608'});
    expect(bulk.applies, 1);
  });

  testWidgets('reprograma solo la referencia completa 601 con plazo 45',
      (tester) async {
    final history = RosaHistory();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CustomerHistoryScreen(
                customer: const BillingCustomer(
                    id: 'rosa',
                    name: 'N55 ROSA OLALLA JARA',
                    commercialName: 'FARMCIA AMIGA',
                    paymentTermDays: 45),
                repository: history,
                onEditTerm: (_) async => null,
                onSchedule: (_) async {},
                onDelete: (_) async => false))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Factura 601'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Factura 601'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reprogram-000000601')), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reprogram-000000601')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Fecha programada actual: 01/09/2026'), findsOneWidget);
    expect(find.text('Nueva fecha calculada: 17/08/2026'), findsOneWidget);
    expect(find.textContaining('45 días'), findsOneWidget);
    expect(find.textContaining('Se modificará únicamente esta factura.'),
        findsOneWidget);
    expect(find.textContaining('Las demás facturas del cliente conservarán'),
        findsOneWidget);
    expect(find.textContaining('¿Deseas continuar?'), findsOneWidget);
    final forbiddenEncodingMarkers =
        String.fromCharCodes([0x00c3, 0x00c2, 0xfffd]);
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(
          text.data?.contains(RegExp('[$forbiddenEncodingMarkers]')) ?? false,
          isFalse);
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Reprogramar factura'));
    await tester.pumpAndSettle();
    expect(history.reprogrammed, 1);
    expect(history.loads, 2); // initial load plus authoritative second read
    expect(find.text('Comentario del calendario: Conservar'), findsOneWidget);
    expect(find.text('Factura 664'), findsOneWidget);
  });

  testWidgets('toda la tarjeta abre modal y la lista no contiene acciones',
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
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byTooltip('Cerrar historial'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar historial'));
    await tester.pumpAndSettle();
    expect(find.text('Historial del cliente'), findsNothing);
    expect(find.text('Editar plazo'), findsNothing);
    expect(find.text('Programar pendientes'), findsNothing);
    expect(find.text('Eliminar cliente'), findsNothing);
  });

  testWidgets('un error real permite reintentar y cargar sin cerrar el modal',
      (tester) async {
    final history = FlakyHistory();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ClientesScreen(
                repository: FakeCustomerTerms(), historyRepository: history))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente configurado'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo cargar el historial.'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(history.attempts, 2);
    expect(find.text('Total histórico'), findsOneWidget);
    expect(find.text('No se pudo cargar el historial.'), findsNothing);
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
        home: Scaffold(
            body: ClientesScreen(
                repository: repository, historyRepository: FakeHistory()))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cliente pendiente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar plazo'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).last, '10');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(repository.lastApplyExisting, isTrue);
    expect(
        find.text('Plazo guardado y 2 facturas programadas.'), findsOneWidget);
  });

  testWidgets('muestra acciones solo dentro del modal y deshabilita programar',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ClientesScreen(
                repository: FakeCustomerTerms(),
                historyRepository: FakeHistory()))));
    await tester.pumpAndSettle();
    expect(find.text('Editar plazo'), findsNothing);
    await tester.tap(find.text('Cliente pendiente'));
    await tester.pumpAndSettle();
    expect(find.text('Editar plazo'), findsOneWidget);
    expect(find.text('Eliminar cliente'), findsOneWidget);
    expect(
        find.byTooltip('Configura primero los días de pago'), findsOneWidget);
    final schedule = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Programar pendientes'));
    expect(schedule.onPressed, isNull);
  });

  testWidgets('confirma, programa una sola vez y muestra resultado',
      (tester) async {
    final repository = FakeCustomerTerms();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ClientesScreen(
                repository: repository, historyRepository: FakeHistory()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente configurado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Programar pendientes'));
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
        home: Scaffold(
            body: ClientesScreen(
                repository: repository, historyRepository: FakeHistory()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente configurado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar cliente'));
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
        home: Scaffold(
            body: ClientesScreen(
                repository: repository, historyRepository: FakeHistory()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente configurado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar cliente'));
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
          home: Scaffold(
              body: ClientesScreen(
                  repository: FakeCustomerTerms(),
                  historyRepository: FakeHistory()))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final cards = find.byType(Card);
      expect(cards, findsNWidgets(2));
      final firstRect = tester.getRect(cards.first);
      expect(firstRect.left, greaterThanOrEqualTo(16));
      expect(firstRect.right, lessThanOrEqualTo(size.width - 16));
      expect(firstRect.height, lessThan(size.width < 620 ? 170 : 100));
      expect(find.text('Editar plazo'), findsNothing);
      await tester.tap(find.text('Cliente configurado'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byTooltip('Cerrar historial'), findsOneWidget);
      expect(find.text('Editar plazo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
