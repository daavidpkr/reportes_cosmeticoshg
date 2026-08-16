import 'package:flutter_test/flutter_test.dart';
import 'package:cosmeticos_hg_reportes/services/supabase_reportes_service.dart';

void main() {
  test('regresión 608 usa fila canónica de julio para general y KPI', () {
    final resultado = construirFilasConsolidadas(
      filas: const [
        {
          'mes_reporte': 'Julio 2026',
          'nro_fila': 17,
          'ref_fact': '000000608',
          'vendedor': 'V1',
          'esmaltes': 0,
          'abonos': [40],
          'numeros_recibo': [null],
          'comentarios_abonos': [null],
        }
      ],
      facturas: const [
        {
          'ref_fact': '000000608',
          'nro_fact': '000000608',
          'cliente': 'N59 LORENA SUSANA OCHOA CORREA',
          'nombre_comercial': 'BAZAR LORENA',
          'fecha': '2026-07-07',
          'venta': 356.35,
        }
      ],
    );
    final invoice = resultado.single;
    expect(invoice.referencia, '000000608');
    expect(invoice.numeroFactura, '000000608');
    expect(invoice.abonos.first.valor, 40);
    expect(invoice.totalAbonos, 40);
    expect(invoice.saldo, closeTo(316.35, .001));
    expect(resultado.fold<double>(0, (sum, row) => sum + row.totalAbonos), 40);
    expect(resultado.fold<double>(0, (sum, row) => sum + row.saldo),
        closeTo(316.35, .001));
  });

  test('consolida meses, referencias, totales y pagos sin duplicar filas', () {
    final filas = <Map<String, dynamic>>[
      {
        'mes_reporte': 'Julio 2026',
        'nro_fila': 1,
        'ref_fact': '592',
        'vendedor': 'V1',
        'esmaltes': 3,
        'abonos': [40, 10, 5],
        'numeros_recibo': [1, 2, 3],
        'comentarios_abonos': ['', '', 'extra'],
      },
      {
        'mes_reporte': 'Agosto 2026',
        'nro_fila': 1,
        'ref_fact': '669',
        'vendedor': 'V2',
        'esmaltes': 2,
        'abonos': [25],
      },
      // Una página repetida no debe duplicar la fila empresarial.
      {
        'mes_reporte': 'Agosto 2026',
        'nro_fila': 1,
        'ref_fact': '669',
        'vendedor': 'V2',
        'esmaltes': 2,
        'abonos': [25],
      },
    ];
    final facturas = <Map<String, dynamic>>[
      {
        'ref_fact': '592',
        'cliente': 'A',
        'nombre_comercial': 'Local A',
        'fecha': '2026-07-31',
        'nro_fact': '000000592',
        'venta': 100,
      },
      {
        'ref_fact': '669',
        'cliente': 'B',
        'nombre_comercial': 'Local B',
        'fecha': '2026-08-01',
        'nro_fact': '000000669',
        'venta': 50,
      },
    ];

    final resultado = construirFilasConsolidadas(
      filas: filas,
      facturas: facturas,
    );

    expect(resultado, hasLength(2));
    expect(resultado.map((fila) => fila.referencia), ['669', '592']);
    expect(resultado.map((fila) => fila.numeroFactura),
        ['000000669', '000000592']);
    expect(resultado.fold<double>(0, (s, f) => s + f.venta), 150);
    expect(resultado.fold<double>(0, (s, f) => s + f.totalAbonos), 80);
    expect(resultado.fold<double>(0, (s, f) => s + f.saldo), 70);
    expect(resultado.fold<int>(0, (s, f) => s + f.esmalte), 5);
    expect(resultado.last.abonos, hasLength(3));
  });

  test('omite referencias vacías y facturas huérfanas', () {
    final resultado = construirFilasConsolidadas(
      filas: const [
        {'mes_reporte': 'Julio 2026', 'nro_fila': 1, 'ref_fact': ' '},
        {'mes_reporte': 'Julio 2026', 'nro_fila': 2, 'ref_fact': '999'},
      ],
      facturas: const [],
    );
    expect(resultado, isEmpty);
  });

  test('recupera más de mil registros mediante rangos consecutivos', () async {
    final fuente = List.generate(2005, (indice) => {'id': indice});
    final resultado = await SupabaseReportesService.obtenerTodasLasPaginas(
      (desde, hasta) async => fuente.sublist(
        desde,
        (hasta + 1).clamp(0, fuente.length),
      ),
    );
    expect(resultado, hasLength(2005));
    expect(resultado.first['id'], 0);
    expect(resultado.last['id'], 2004);
  });
}
