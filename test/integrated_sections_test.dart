import 'package:cosmeticos_hg_reportes/models/payment_calendar_entry.dart';
import 'package:cosmeticos_hg_reportes/screens/carga_facturas_screen.dart';
import 'package:cosmeticos_hg_reportes/screens/payment_calendar/payment_calendar_screen.dart';
import 'package:cosmeticos_hg_reportes/services/payment_calendar_repository.dart';
import 'package:cosmeticos_hg_reportes/theme/hg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CalendarSource implements PaymentCalendarDataSource {
  int reads = 0;

  @override
  Future<List<PaymentCalendarEntry>> listMonth(DateTime month) async {
    reads++;
    return const [];
  }

  @override
  Future<PaymentCalendarEntry> updateReminder({
    required PaymentCalendarEntry entry,
    required DateTime reminderDate,
    required String comment,
  }) async =>
      entry;
}

void main() {
  testWidgets('calendario incrustado no crea AppBar ni duplica consultas',
      (tester) async {
    final source = _CalendarSource();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [HgThemeColors.light]),
      home: Scaffold(
        appBar: AppBar(title: const Text('Cosméticos HG')),
        body: PaymentCalendarView(
          repository: source,
          initialMonth: DateTime(2026, 8),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Cosméticos HG'), findsOneWidget);
    expect(find.text('Calendario de cobros'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(source.reads, 1);

    await tester.pump();
    expect(source.reads, 1);
  });

  testWidgets('carga incrustada conserva mes y vuelve por callback',
      (tester) async {
    var returned = false;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [HgThemeColors.light]),
      home: Scaffold(
        appBar: AppBar(title: const Text('Cosméticos HG')),
        body: CargaFacturasView(
          mes: 8,
          anio: 2026,
          onVolver: () => returned = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Carga de facturas'), findsOneWidget);
    expect(find.text('Facturas de 08/2026'), findsOneWidget);
    expect(find.text('Seleccionar facturas'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Volver al reporte de ventas'));
    expect(returned, isTrue);
  });
}
