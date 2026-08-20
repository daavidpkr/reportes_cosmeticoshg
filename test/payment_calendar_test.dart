import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmeticos_hg_reportes/models/payment_calendar_entry.dart';
import 'package:cosmeticos_hg_reportes/models/billing_customer.dart';
import 'package:cosmeticos_hg_reportes/models/customer_history.dart';
import 'package:cosmeticos_hg_reportes/models/payment_calendar_rules.dart';
import 'package:cosmeticos_hg_reportes/screens/payment_calendar/payment_calendar_controller.dart';
import 'package:cosmeticos_hg_reportes/screens/payment_calendar/payment_calendar_screen.dart';
import 'package:cosmeticos_hg_reportes/screens/payment_calendar/widgets/pending_invoice_card.dart';
import 'package:cosmeticos_hg_reportes/services/payment_calendar_repository.dart';
import 'package:cosmeticos_hg_reportes/services/customer_history_repository.dart';

PaymentCalendarEntry entry(String id, DateTime date,
        {double balance = 10, String comment = ''}) =>
    PaymentCalendarEntry(
        reminderId: 'r$id',
        facturaId: id,
        invoiceNumber: id.padLeft(9, '0'),
        cliente: 'Cliente $id',
        nombreComercial: 'Comercial $id',
        invoiceDate: DateTime(2026, 8, 1),
        reminderDate: date,
        balance: balance,
        comment: comment);

class FakeCalendarRepository
    implements
        PaymentCalendarDataSource,
        CalendarPaymentDataSource,
        CalendarCustomerDataSource {
  FakeCalendarRepository(this.values);
  List<PaymentCalendarEntry> values;
  bool fail = false;
  int reads = 0;
  int payments = 0;
  String? resolvedInvoice;
  BillingCustomer? resolvedCustomer;

  @override
  Future<BillingCustomer?> resolveCustomer(String facturaId) async {
    resolvedInvoice = facturaId;
    return resolvedCustomer;
  }

  @override
  Future<List<PaymentCalendarEntry>> listMonth(DateTime month) async {
    reads++;
    if (fail) throw Exception('remote');
    return values
        .where((e) =>
            e.reminderDate.year == month.year &&
            e.reminderDate.month == month.month &&
            e.balance > .005)
        .toList();
  }

  @override
  Future<PaymentCalendarEntry> updateReminder(
      {required PaymentCalendarEntry entry,
      required DateTime reminderDate,
      required String comment}) async {
    if (fail) throw Exception('remote');
    final saved = entry.copyWith(
        reminderDate: adjustedReminderDate(reminderDate), comment: comment);
    values = [
      for (final value in values)
        if (value.reminderId != entry.reminderId) value,
      saved
    ];
    return saved;
  }

  @override
  Future<double> recordPayment(
      {required PaymentCalendarEntry entry,
      required double amount,
      String comment = '',
      int? receiptNumber,
      bool payInFull = false}) async {
    if (fail || amount <= 0 || amount > entry.balance + .005) {
      throw Exception('remote');
    }
    payments++;
    final remaining = payInFull
        ? 0.0
        : (entry.balance - amount).clamp(0, double.infinity).toDouble();
    values = [
      for (final value in values)
        if (value.reminderId == entry.reminderId)
          PaymentCalendarEntry(
              reminderId: value.reminderId,
              facturaId: value.facturaId,
              invoiceNumber: value.invoiceNumber,
              cliente: value.cliente,
              nombreComercial: value.nombreComercial,
              invoiceDate: value.invoiceDate,
              reminderDate: value.reminderDate,
              balance: remaining,
              comment: value.comment)
        else
          value
    ];
    return remaining;
  }
}

class FakeCalendarHistory implements CustomerHistoryDataSource {
  String? customerId;

  @override
  Future<CustomerHistoryPage> load(
      {required String customerId,
      required int offset,
      String status = 'all',
      String search = '',
      String sort = 'recent'}) async {
    this.customerId = customerId;
    return const CustomerHistoryPage(
        summary: CustomerHistorySummary(
            totalSales: 100,
            totalPaid: 40,
            balance: 60,
            totalInvoices: 1,
            paidInvoices: 0,
            pendingInvoices: 1,
            overdueInvoices: 0,
            cancelledInvoices: 0),
        invoices: [],
        filteredCount: 0);
  }

  @override
  Future<InvoiceTermRecalculation> previewRecalculation(String reference) =>
      throw UnimplementedError();

  @override
  Future<InvoiceTermRecalculation> reprogramInvoice(
          InvoiceTermRecalculation preview) =>
      throw UnimplementedError();
}

void main() {
  test('referencias visibles no muestran ceros a la izquierda', () {
    expect(visibleInvoiceReference('000000674'), '674');
    expect(visibleInvoiceReference('000'), '0');
    expect(visibleInvoiceReference('FAC-001'), 'FAC-001');
  });

  group('reglas del calendario', () {
    test('comienza en lunes para meses que comienzan cualquier día', () {
      for (var month = 1; month <= 12; month++) {
        final days = mondayFirstCalendarDays(DateTime(2026, month));
        expect(days.first.weekday, DateTime.monday);
        expect(days.last.weekday, DateTime.sunday);
        expect(days.any((d) => d.day == 1 && d.month == month), isTrue);
      }
    });
    test('febrero normal y bisiesto', () {
      expect(DateTime(2025, 3, 0).day, 28);
      expect(DateTime(2024, 3, 0).day, 29);
      expect(
          mondayFirstCalendarDays(DateTime(2024, 2)).where((d) => d.month == 2),
          hasLength(29));
    });
    test('navegación matemática cruza diciembre y enero', () {
      expect(DateTime(2026, 12 + 1), DateTime(2027, 1));
      expect(DateTime(2026, 1 - 1), DateTime(2025, 12));
    });
    test('sábado y domingo se ajustan al lunes', () {
      expect(
          adjustedReminderDate(DateTime(2026, 8, 15)), DateTime(2026, 8, 17));
      expect(
          adjustedReminderDate(DateTime(2026, 8, 16)), DateTime(2026, 8, 17));
    });
    test('agrupa cantidades y elimina duplicados del mismo día', () {
      final day = DateTime(2026, 8, 17);
      final grouped =
          entriesByDay([entry('1', day), entry('1', day), entry('2', day)]);
      expect(grouped[day], hasLength(2));
      expect(grouped[DateTime(2026, 8, 18)], isNull);
    });
  });

  group('coordinación y persistencia', () {
    test('reprograma, conserva segunda lectura y no duplica', () async {
      final repo = FakeCalendarRepository([entry('1', DateTime(2026, 8, 10))]);
      final controller = PaymentCalendarController(
          repository: repo, initialMonth: DateTime(2026, 8));
      await controller.load();
      expect(
          await controller.update(
              controller.entries.single, DateTime(2026, 8, 15), 'Llamar'),
          isTrue);
      expect(controller.grouped[DateTime(2026, 8, 10)], isNull);
      expect(
          controller.grouped[DateTime(2026, 8, 17)]!.single.comment, 'Llamar');
      await controller.load(refresh: true);
      expect(controller.entries, hasLength(1));
      expect(controller.entries.single.reminderDate, DateTime(2026, 8, 17));
    });
    test('crea, edita y elimina comentario', () async {
      final repo = FakeCalendarRepository([entry('1', DateTime(2026, 8, 10))]);
      var current = repo.values.single;
      current = await repo.updateReminder(
          entry: current, reminderDate: current.reminderDate, comment: 'Uno');
      current = await repo.updateReminder(
          entry: current, reminderDate: current.reminderDate, comment: 'Dos');
      current = await repo.updateReminder(
          entry: current, reminderDate: current.reminderDate, comment: '');
      expect(current.comment, isEmpty);
    });
    test('fallo remoto no cambia el estado', () async {
      final original = entry('1', DateTime(2026, 8, 10));
      final repo = FakeCalendarRepository([original]);
      final controller = PaymentCalendarController(
          repository: repo, initialMonth: DateTime(2026, 8));
      await controller.load();
      repo.fail = true;
      expect(await controller.update(original, DateTime(2026, 8, 20), ''),
          isFalse);
      expect(controller.entries.single.reminderDate, original.reminderDate);
    });
    test('abono total desaparece tras actualizar', () async {
      final repo = FakeCalendarRepository([entry('1', DateTime(2026, 8, 10))]);
      final controller = PaymentCalendarController(
          repository: repo, initialMonth: DateTime(2026, 8));
      await controller.load();
      repo.values = [entry('1', DateTime(2026, 8, 10), balance: 0)];
      await controller.load(refresh: true);
      expect(controller.entries, isEmpty);
    });
    test('abono parcial actualiza saldo y pago total retira la factura',
        () async {
      final repo = FakeCalendarRepository(
          [entry('1', DateTime(2026, 8, 10), balance: 100)]);
      final controller = PaymentCalendarController(
          repository: repo, initialMonth: DateTime(2026, 8));
      await controller.load();
      expect(await controller.recordPayment(controller.entries.single, 40),
          isTrue);
      expect(controller.entries.single.balance, 60);
      expect(await controller.payInFull(controller.entries.single), isTrue);
      expect(controller.entries, isEmpty);
      expect(repo.payments, 2);
    });
  });

  group('interfaz adaptable', () {
    Future<void> pump(WidgetTester tester, Size size,
        List<PaymentCalendarEntry> values) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: PaymentCalendarScreen(
              repository: FakeCalendarRepository(values),
              initialMonth: DateTime(2026, 8))));
      await tester.pumpAndSettle();
    }

    testWidgets('escritorio muestra mes, hoy y cantidad sin desbordar',
        (tester) async {
      await pump(
          tester, const Size(1200, 900), [entry('684', DateTime(2026, 8, 17))]);
      expect(find.text('Agosto 2026'), findsOneWidget);
      expect(find.text('Hoy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('móvil abre día vacío y popup con una factura', (tester) async {
      await pump(tester, const Size(390, 844),
          [entry('684', DateTime(2026, 8, 17), comment: 'Llamar')]);
      await tester
          .tap(find.bySemanticsLabel(RegExp('17, 1 facturas pendientes')));
      await tester.pumpAndSettle();
      expect(find.text('Facturas pendientes'), findsOneWidget);
      expect(find.text('REF. 684'), findsOneWidget);
      expect(find.textContaining('Llamar'), findsOneWidget);
      expect(find.text('Historial'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('invoice-actions-grid')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('Android muestra solamente día y contador en cada celda',
        (tester) async {
      await pump(tester, const Size(390, 844), [
        entry('684', DateTime(2026, 8, 17)),
        entry('685', DateTime(2026, 8, 17)),
        entry('686', DateTime(2026, 8, 17)),
        entry('687', DateTime(2026, 8, 17)),
      ]);
      expect(find.text('4'), findsWidgets);
      expect(find.textContaining('Cliente 684'), findsNothing);
      expect(find.textContaining('684 ·'), findsNothing);
      expect(find.text('+3'), findsNothing);
      await tester
          .tap(find.bySemanticsLabel(RegExp('17, 4 facturas pendientes')));
      await tester.pumpAndSettle();
      expect(find.text('REF. 684'), findsOneWidget);
      expect(find.byType(PendingInvoiceCard), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('historial no resoluble informa sin cerrar el día',
        (tester) async {
      final repository =
          FakeCalendarRepository([entry('684', DateTime(2026, 8, 17))]);
      await tester.binding.setSurfaceSize(const Size(320, 700));
      await tester.pumpWidget(MaterialApp(
          home: PaymentCalendarScreen(
              repository: repository, initialMonth: DateTime(2026, 8))));
      await tester.pumpAndSettle();
      await tester
          .tap(find.bySemanticsLabel(RegExp('17, 1 facturas pendientes')));
      await tester.pumpAndSettle();
      await tester.drag(
          find.byType(PendingInvoiceCard).first, const Offset(0, -260));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();
      expect(repository.resolvedInvoice, '684');
      expect(find.text('Facturas pendientes'), findsOneWidget);
      expect(find.textContaining('No se pudo identificar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ver historial usa el customer_id canónico y vuelve al día',
        (tester) async {
      final repository =
          FakeCalendarRepository([entry('684', DateTime(2026, 8, 17))])
            ..resolvedCustomer = const BillingCustomer(
                id: 'customer-684',
                name: 'Cliente 684',
                commercialName: 'Comercial 684',
                paymentTermDays: 30);
      final history = FakeCalendarHistory();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(MaterialApp(
          home: PaymentCalendarScreen(
              repository: repository,
              historyRepository: history,
              initialMonth: DateTime(2026, 8))));
      await tester.pumpAndSettle();
      await tester
          .tap(find.bySemanticsLabel(RegExp('17, 1 facturas pendientes')));
      await tester.pumpAndSettle();
      await tester.drag(
          find.byType(PendingInvoiceCard).first, const Offset(0, -260));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();
      expect(repository.resolvedInvoice, '684');
      expect(history.customerId, 'customer-684');
      expect(find.text('Historial del cliente'), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar historial'));
      await tester.pumpAndSettle();
      expect(find.text('Facturas pendientes'), findsOneWidget);
      expect(find.text('Agosto 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('móvil usa días abreviados y zoom con límites y ajuste',
        (tester) async {
      await pump(tester, const Size(320, 700), [
        entry('1', DateTime(2026, 8, 17)),
        entry('2', DateTime(2026, 8, 17)),
      ]);
      for (final label in ['L', 'M', 'X', 'J', 'V', 'S', 'D']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('+1'), findsNothing);
      final viewer = tester.widget<InteractiveViewer>(
          find.byKey(const ValueKey('payment-calendar-zoom')));
      final transformation = viewer.transformationController!;
      expect(transformation.value.getMaxScaleOnAxis(), 1);

      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byKey(const ValueKey('calendar-zoom-in')));
        await tester.pump();
      }
      expect(transformation.value.getMaxScaleOnAxis(), 2);
      expect(
          tester
              .widget<IconButton>(
                  find.byKey(const ValueKey('calendar-zoom-in')))
              .onPressed,
          isNull);

      await tester.tap(find.byKey(const ValueKey('calendar-zoom-fit')));
      await tester.pump();
      expect(transformation.value.getMaxScaleOnAxis(), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pellizcar amplía sin abrir accidentalmente el día',
        (tester) async {
      await pump(
          tester, const Size(390, 844), [entry('1', DateTime(2026, 8, 17))]);
      final center =
          tester.getCenter(find.byKey(const ValueKey('payment-calendar-zoom')));
      final first =
          await tester.startGesture(center - const Offset(20, 0), pointer: 1);
      final second =
          await tester.startGesture(center + const Offset(20, 0), pointer: 2);
      await first.moveTo(center - const Offset(70, 0));
      await second.moveTo(center + const Offset(70, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump(const Duration(milliseconds: 150));

      final viewer = tester.widget<InteractiveViewer>(
          find.byKey(const ValueKey('payment-calendar-zoom')));
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(),
          greaterThan(1));
      expect(find.text('Facturas pendientes'), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        'regresión 608 confirma persistencia y refresca consumidores antes del éxito',
        (tester) async {
      final repository = FakeCalendarRepository(
          [entry('000000608', DateTime(2026, 8, 6), balance: 356.35)]);
      var refreshes = 0;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PaymentCalendarView(
                  repository: repository,
                  initialMonth: DateTime(2026, 8),
                  onPaymentPersisted: () async => refreshes++))));
      await tester.pumpAndSettle();
      await tester
          .tap(find.bySemanticsLabel(RegExp('6, 1 facturas pendientes')));
      await tester.pumpAndSettle();
      expect(find.text('REF. 608'), findsOneWidget);
      await tester.tap(find.text('Abono'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Valor del abono'), '40');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(repository.payments, 1);
      expect(repository.values.single.balance, closeTo(316.35, .001));
      expect(refreshes, 1);
      expect(find.text('Abono registrado correctamente.'), findsOneWidget);
    });
    testWidgets('popup lista varias facturas con datos completos',
        (tester) async {
      await pump(tester, const Size(800, 900), [
        entry('1', DateTime(2026, 8, 17)),
        entry('2', DateTime(2026, 8, 17))
      ]);
      await tester
          .tap(find.bySemanticsLabel(RegExp('17, 2 facturas pendientes')));
      await tester.pumpAndSettle();
      expect(find.text('REF. 1'), findsOneWidget);
      expect(find.text('REF. 2'), findsOneWidget);
      expect(find.textContaining('Saldo pendiente'), findsNWidgets(2));
    });
  });
}
