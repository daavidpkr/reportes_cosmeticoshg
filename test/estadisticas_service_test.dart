import 'package:cosmeticos_hg_reportes/services/estadisticas_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final data = construirEstadisticas(
    reportes: const [
      {'anio': 2026, 'mes': 7},
      {'anio': 2026, 'mes': 8},
    ],
    filas: const [
      {
        'mes_reporte': 'Julio 2026',
        'ref_fact': '1',
        'vendedor': '01 - Ana',
        'esmaltes': 2,
        'abonos': [100]
      },
      {
        'mes_reporte': 'Agosto 2026',
        'ref_fact': '2',
        'vendedor': '01 - Ana',
        'esmaltes': 4,
        'abonos': [100, 33.68, 200]
      },
      {
        'mes_reporte': 'Agosto 2026',
        'ref_fact': '3',
        'vendedor': '02 - Luz',
        'esmaltes': 1,
        'abonos': [50]
      },
    ],
    facturas: const [
      {
        'ref_fact': '1',
        'cliente': 'Ruth Sánchez',
        'fecha': '07/07/2026',
        'venta': 200
      },
      {
        'ref_fact': '2',
        'cliente': 'Ruth Sánchez',
        'fecha': '05/08/2026',
        'venta': 900
      },
      {
        'ref_fact': '3',
        'cliente': '  RUTH   SÁNCHEZ ',
        'fecha': '12/08/2026',
        'venta': 100
      },
    ],
  );

  test('mantiene ventas, todos los abonos y saldo del reporte', () {
    final r = data.resumen(const PeriodoEstadisticas.mes(2026, 8));
    expect(r.ventas, 1000);
    expect(r.cobrado, closeTo(383.68, .000001));
    expect(r.porCobrar, closeTo(616.32, .000001));
    expect(r.facturas, 2);
    expect(r.clientes, 1);
    expect(r.esmaltes, 5);
    expect(r.ticketPromedio, 500);
  });

  test('filtra año e histórico y encuentra período anterior', () {
    expect(data.resumen(const PeriodoEstadisticas.anio(2026)).ventas, 1200);
    expect(data.resumen(const PeriodoEstadisticas.todo()).facturas, 3);
    expect(
        data.anterior(const PeriodoEstadisticas.mes(2026, 8))!.id, '2026-07');
  });

  test('agrupa clientes, ordena vendedores y promedia fechas reales', () {
    const agosto = PeriodoEstadisticas.mes(2026, 8);
    expect(data.clientesTop(agosto), hasLength(1));
    expect(data.vendedores(agosto).first.nombre, '01 - Ana');
    final promedios = data.promedioPorDia(agosto);
    expect(promedios[2].promedio, 500); // dos miércoles distintos
    expect(data.mayorVenta(agosto)!.referencia, '2');
  });

  test('evita divisiones inválidas en períodos vacíos', () {
    final r = data.resumen(const PeriodoEstadisticas.mes(2025, 1));
    expect(r.ticketPromedio, 0);
    expect(r.porcentajeCobranza, 0);
  });
}
