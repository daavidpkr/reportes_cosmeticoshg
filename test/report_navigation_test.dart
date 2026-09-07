import 'package:cosmeticos_hg_reportes/screens/reporte_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each primary mobile destination has one canonical index', () {
    expect(mobileNavigationIndex(ReportDestination.sales), 0);
    expect(mobileNavigationIndex(ReportDestination.general), 1);
    expect(mobileNavigationIndex(ReportDestination.clients), 2);
    expect(mobileNavigationIndex(ReportDestination.calendar), 3);
    expect(mobileNavigationIndex(ReportDestination.globalSearch), isNull);
    expect(mobileNavigationIndex(ReportDestination.sellers), isNull);
  });

  test('mobile selection and visible destination use the same mapping', () {
    for (var index = 0; index < 4; index++) {
      final destination = destinationForMobileIndex(index);
      expect(mobileNavigationIndex(destination), index);
    }
  });
}
