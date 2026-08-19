import 'package:cosmeticos_hg_reportes/screens/reporte_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('navegación Android intercambia Clientes y Cobros mensuales', () {
    expect(mobileReportNavigationLabels,
        ['Ventas', 'General', 'Clientes', 'Calendario']);
    expect(mobileReportMenuSectionLabels,
        ['Cobros mensuales', 'Vendedores', 'Estadísticas']);
    expect(mobileReportMenuSectionLabels, isNot(contains('Clientes')));
    expect(mobileReportNavigationLabels, isNot(contains('Cobros')));
  });
}
