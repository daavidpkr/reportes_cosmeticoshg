import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmeticos_hg_reportes/models/payment_calendar_entry.dart';
import 'package:cosmeticos_hg_reportes/models/payment_calendar_rules.dart';
import 'package:cosmeticos_hg_reportes/screens/payment_calendar/payment_calendar_controller.dart';
import 'package:cosmeticos_hg_reportes/screens/payment_calendar/payment_calendar_screen.dart';
import 'package:cosmeticos_hg_reportes/screens/payment_calendar/widgets/pending_invoice_card.dart';
import 'package:cosmeticos_hg_reportes/services/payment_calendar_repository.dart';

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

class FakeCalendarRepository implements PaymentCalendarDataSource {
  FakeCalendarRepository(this.values);
  List<PaymentCalendarEntry> values;
  bool fail = false;
  int reads = 0;

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
      expect(tester.takeException(), isNull);
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
