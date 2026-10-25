import 'package:cosmeticos_hg_reportes/screens/reporte_screen.dart';
import 'package:cosmeticos_hg_reportes/services/invoice_batch_importer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each primary mobile destination has one canonical index', () {
    expect(mobileReportNavigationLabels,
        ['Ventas', 'Búsqueda general', 'Clientes', 'Calendario']);
    expect(mobileNavigationIndex(ReportDestination.sales), 0);
    expect(mobileNavigationIndex(ReportDestination.globalSearch), 1);
    expect(mobileNavigationIndex(ReportDestination.clients), 2);
    expect(mobileNavigationIndex(ReportDestination.calendar), 3);
    expect(mobileNavigationIndex(ReportDestination.sellers), isNull);
    expect(mobileNavigationIndex(ReportDestination.catalogs), isNull);
  });

  test('mobile selection and visible destination use the same mapping', () {
    for (var index = 0; index < 4; index++) {
      final destination = destinationForMobileIndex(index);
      expect(mobileNavigationIndex(destination), index);
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'la barra móvil con cuatro destinos no desborda en ${brightness.name}',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          bottomNavigationBar: NavigationBar(
            selectedIndex: 1,
            destinations: mobileReportNavigationDestinations,
          ),
        ),
      ));

      final navigationBar =
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navigationBar.selectedIndex, 1);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  }

  test('solo los cuatro destinos inferiores son principales', () {
    expect(isPrimaryReportDestination(ReportDestination.sales), isTrue);
    expect(isPrimaryReportDestination(ReportDestination.globalSearch), isTrue);
    expect(isPrimaryReportDestination(ReportDestination.clients), isTrue);
    expect(isPrimaryReportDestination(ReportDestination.calendar), isTrue);
    expect(isPrimaryReportDestination(ReportDestination.monthlyCollections),
        isFalse);
    expect(isPrimaryReportDestination(ReportDestination.sellers), isFalse);
    expect(isPrimaryReportDestination(ReportDestination.statistics), isFalse);
    expect(
        isPrimaryReportDestination(ReportDestination.invoiceImport), isFalse);
    expect(isPrimaryReportDestination(ReportDestination.catalogs), isFalse);
  });

  test('ordena referencias naturalmente sin modificar sus ceros', () {
    final referencias = ['10', '0002', '1']..sort(compareInvoiceReferences);

    expect(referencias, ['1', '0002', '10']);
  });

  testWidgets('el logo abre, cierra y navega con una sola selección',
      (tester) async {
    var current = ReportDestination.sales;

    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        return Scaffold(
          appBar: AppBar(
            title: ReportLogoMenu(
              destination: current,
              onSelected: (destination) =>
                  setState(() => current = destination),
            ),
          ),
        );
      }),
    ));

    final logo = find.byKey(const Key('report-logo-menu'));
    await tester.tap(logo, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Vendedores'), findsOneWidget);
    expect(find.text('Estadísticas'), findsOneWidget);

    await tester.tap(find.widgetWithText(
      CheckedPopupMenuItem<ReportDestination>,
      'Vendedores',
    ));
    await tester.pumpAndSettle();
    expect(current, ReportDestination.sellers);
    expect(find.text('Vendedores'), findsNothing);

    await tester.tap(logo, warnIfMissed: false);
    await tester.pumpAndSettle();
    final checks = tester
        .widgetList<CheckedPopupMenuItem<ReportDestination>>(
          find.byType(CheckedPopupMenuItem<ReportDestination>),
        )
        .where((item) => item.checked);
    expect(checks, hasLength(1));

    await tester.tap(logo, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Vendedores'), findsNothing);

    await tester.tap(logo, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Vendedores'), findsNothing);

    await tester.tap(logo, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(current, ReportDestination.sellers);
    expect(find.text('Vendedores'), findsNothing);

    await tester.tap(logo, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 500));
    await tester.pumpAndSettle();
    expect(find.text('Estadísticas'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('el logo no desborda a 320 px en modo ${brightness.name}',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: ReportLogoMenu(
              compact: true,
              destination: ReportDestination.sales,
              onSelected: (_) {},
            ),
            actions: const [
              SizedBox(width: 48, child: Icon(Icons.menu)),
            ],
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel('Menú de Cosméticos HG'),
        findsOneWidget,
      );
    });
  }
}
