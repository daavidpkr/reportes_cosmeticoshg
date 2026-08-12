import 'package:cosmeticos_hg_reportes/models/fila_venta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('número de recibo', () {
    test('acepta enteros positivos y el máximo seguro', () {
      for (final value in ['1', '4587', '$maxNumeroReciboSeguro']) {
        expect(validarNumeroRecibo(value), isNull);
      }
    });

    test('acepta vacío para cualquier abono', () {
      expect(validarNumeroRecibo(''), isNull);
      expect(validarNumeroRecibo('   '), isNull);
      expect(validarNumeroRecibo('0'), isNotNull);
      for (final value in [
        '-25',
        '12.5',
        '12,5',
        'ABC',
        'A123',
        'REC-123',
        '12 34',
        '9007199254740992',
        '9223372036854775808',
      ]) {
        expect(validarNumeroRecibo(value), isNotNull);
      }
    });

    test('el valor del abono debe ser numérico y mayor que cero', () {
      for (final value in ['', '0', '-1', 'letras', 'Infinity']) {
        expect(validarValorAbono(value), isNotNull);
      }
      expect(validarValorAbono('13.50'), isNull);
      expect(validarValorAbono('13,50'), isNull);
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
