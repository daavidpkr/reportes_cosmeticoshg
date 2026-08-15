import 'package:cosmeticos_hg_reportes/screens/reporte_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('densidad responsive compartida de reportes', () {
    test('selecciona compacto para 1024 y 1280', () {
      for (final width in [1024.0, 1280.0]) {
        final layout = ReportResponsiveLayout.forWidth(width);
        expect(layout.density, ReportDensity.compact);
        expect(layout.pagePadding, 12);
        expect(layout.tableScale, .78);
      }
    });

    test('selecciona normal para 1366', () {
      final layout = ReportResponsiveLayout.forWidth(1366);
      expect(layout.density, ReportDensity.normal);
      expect(layout.pagePadding, 20);
      expect(layout.tableScale, .9);
    });

    test('selecciona amplio para 1600 y 1920', () {
      for (final width in [1600.0, 1920.0]) {
        final layout = ReportResponsiveLayout.forWidth(width);
        expect(layout.density, ReportDensity.wide);
        expect(layout.pagePadding, 28);
        expect(layout.tableScale, 1);
      }
    });

    test('la tabla distingue interaccion sin duplicar modos de layout', () {
      expect(ReportTableMode.values,
          [ReportTableMode.editable, ReportTableMode.readOnly]);
    });
  });
}
