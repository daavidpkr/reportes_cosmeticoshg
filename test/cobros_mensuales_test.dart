import 'package:cosmeticos_hg_reportes/services/supabase_reportes_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('suma venta menos todos los abonos y conserva saldos cero', () {
    final cobros = calcularCobrosMensuales(
      reportes: [
        {'anio': 2025, 'mes': 12},
        {'anio': 2026, 'mes': 1},
        {'anio': 2026, 'mes': 7},
      ],
      filas: [
        {
          'mes_reporte': 'Diciembre 2025',
          'ref_fact': '001',
          'abonos': [100, 50],
        },
        {
          'mes_reporte': 'Enero 2026',
          'ref_fact': '002',
          'abonos': [245.50, 254.50],
        },
        {
          'mes_reporte': 'Julio 2026',
          'ref_fact': '003',
          'abonos': [100, 33.68, 200],
        },
      ],
      facturas: [
        {'ref_fact': '001', 'venta': 200},
        {'ref_fact': '002', 'venta': 500},
        {'ref_fact': '003', 'venta': 900},
      ],
    );

    expect(cobros.map((cobro) => cobro.nombre), [
      'Diciembre 2025',
      'Enero 2026',
      'Julio 2026',
    ]);
    expect(cobros[0].valorPorCobrar, 50);
    expect(cobros[1].valorPorCobrar, 0);
    expect(cobros[2].valorPorCobrar, closeTo(566.32, 0.000001));
  });

  test('solo devuelve reportes realmente creados', () {
    final cobros = calcularCobrosMensuales(
      reportes: [
        {'anio': 2026, 'mes': 5},
      ],
      filas: const [],
      facturas: const [],
    );

    expect(cobros, hasLength(1));
    expect(cobros.single.nombre, 'Mayo 2026');
    expect(cobros.single.valorPorCobrar, 0);
  });
}
