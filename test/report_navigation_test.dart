import 'package:cosmeticos_hg_reportes/screens/reporte_screen.dart';
import 'package:cosmeticos_hg_reportes/services/invoice_batch_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each primary mobile destination has one canonical index', () {
    expect(mobileReportNavigationLabels, ['Ventas', 'Clientes', 'Calendario']);
    expect(mobileNavigationIndex(ReportDestination.sales), 0);
    expect(mobileNavigationIndex(ReportDestination.clients), 1);
    expect(mobileNavigationIndex(ReportDestination.calendar), 2);
    expect(mobileNavigationIndex(ReportDestination.globalSearch), isNull);
    expect(mobileNavigationIndex(ReportDestination.sellers), isNull);
  });

  test('mobile selection and visible destination use the same mapping', () {
    for (var index = 0; index < 3; index++) {
      final destination = destinationForMobileIndex(index);
      expect(mobileNavigationIndex(destination), index);
    }
  });

  test('ordena referencias naturalmente sin modificar sus ceros', () {
    final referencias = ['10', '0002', '1']..sort(compareInvoiceReferences);

    expect(referencias, ['1', '0002', '10']);
  });
}
