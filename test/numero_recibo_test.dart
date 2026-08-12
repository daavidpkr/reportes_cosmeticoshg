import 'package:cosmeticos_hg_reportes/models/fila_venta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('número de recibo', () {
    test('acepta enteros positivos y el máximo seguro', () {
      for (final value in ['1', '4587', '$maxNumeroReciboSeguro']) {
        expect(validarNumeroRecibo(value), isNull);
      }
    });

    test('acepta vacío y rechaza cero, negativos, decimales y caracteres', () {
      expect(validarNumeroRecibo(''), isNull);
      expect(
        validarNumeroRecibo('0'),
        'El número de recibo debe ser mayor que cero.',
      );
      for (final value in [
        '-25',
        '12.5',
        '12,5',
        'ABC',
        'A123',
        'REC-123',
        '12 34',
        '9007199254740992',
      ]) {
        expect(validarNumeroRecibo(value), contains('números enteros'));
      }
    });

    test('serializa, recupera y conserva la ausencia histórica', () {
      final actual = Abono(
        valor: 100.50,
        numeroRecibo: 4587,
        comentario: 'Transferencia',
      );
      final recuperado = Abono.fromJson(actual.toJson());
      expect(recuperado.valor, 100.50);
      expect(recuperado.numeroRecibo, 4587);
      expect(recuperado.comentario, 'Transferencia');

      final historico = Abono.fromJson({'valor': 75, 'comentario': ''});
      expect(historico.numeroRecibo, isNull);
    });

    test('cada abono conserva su recibo al editar y eliminar el intermedio',
        () {
      final fila = FilaVenta(
        numero: 1,
        abonos: [
          Abono(valor: 10, numeroRecibo: 1001),
          Abono(valor: 20, numeroRecibo: 1002),
          Abono(valor: 30, numeroRecibo: 1003),
        ],
      );
      fila.abonos[1]
        ..valor = 25
        ..numeroRecibo = 2002
        ..comentario = 'Editado';
      expect(fila.abonos.map((item) => item.numeroRecibo), [1001, 2002, 1003]);
      fila.abonos.removeAt(1);
      expect(fila.abonos.map((item) => item.numeroRecibo), [1001, 1003]);
    });
  });
}
