import 'package:cosmeticos_hg_reportes/models/fila_venta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('estados de factura', () {
    test('ANUL y ANULADA se consideran anuladas', () {
      for (final seller in ['ANUL', ' anul ', 'ANULADA']) {
        final row = FilaVenta(
          numero: 1,
          vendedor: seller,
          venta: 100,
          abonos: [Abono(valor: 20)],
        );

        expect(row.anulada, isTrue);
        expect(row.pagada, isFalse);
        expect(row.abonoParcial, isFalse);
      }
    });

    test('solo el abono mayor que cero con saldo pendiente es parcial', () {
      FilaVenta row(List<Abono> payments) => FilaVenta(
            numero: 1,
            vendedor: '01 - Ana',
            venta: 100,
            abonos: payments,
          );

      expect(row([Abono()]).abonoParcial, isFalse);
      expect(row([Abono(valor: 20)]).abonoParcial, isTrue);
      expect(row([Abono(valor: 100)]).abonoParcial, isFalse);
    });
  });
}
