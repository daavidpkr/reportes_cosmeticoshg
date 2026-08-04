import 'package:cosmeticos_hg_reportes/services/facturas_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final store = FacturasStore.instance;

  setUp(() {
    store
      ..limpiar()
      ..mesPermitido = null
      ..anioPermitido = null;
  });

  test('extrae el nombre comercial después de la barra', () {
    store.agregarDesdeTexto('''
      <factura>
        <secuencial>000000668</secuencial>
        <razonSocialComprador>ANGELITA SANCHEZ</razonSocialComprador>
        <direccionComprador>AV DE LAS AMERICAS | FARMACIA ESPERANZA</direccionComprador>
        <fechaEmision>31/07/2026</fechaEmision>
        <importeTotal>59.21</importeTotal>
      </factura>
    ''');

    expect(store.buscar('668')?.nombreComercial, 'FARMACIA ESPERANZA');
  });

  test('deja vacío el nombre comercial cuando no existe barra', () {
    store.agregarDesdeTexto('''
      <factura>
        <secuencial>000000669</secuencial>
        <direccionComprador>AV DE LAS AMERICAS</direccionComprador>
      </factura>
    ''');

    expect(store.buscar('669')?.nombreComercial, isEmpty);
  });

  test('rechaza una factura que no pertenece al reporte mensual', () {
    store
      ..mesPermitido = 7
      ..anioPermitido = 2026;

    final resultado = store.agregarDesdeTexto('''
      <factura>
        <secuencial>000000670</secuencial>
        <fechaEmision>01/08/2026</fechaEmision>
        <importeTotal>20.00</importeTotal>
      </factura>
    ''');

    expect(resultado, ResultadoFactura.mesIncorrecto);
    expect(store.buscar('670'), isNull);
  });

  test('acepta una factura del mes y año del reporte', () {
    store
      ..mesPermitido = 7
      ..anioPermitido = 2026;

    final resultado = store.agregarDesdeTexto('''
      <factura>
        <secuencial>000000671</secuencial>
        <fechaEmision>15/07/2026</fechaEmision>
        <importeTotal>20.00</importeTotal>
      </factura>
    ''');

    expect(resultado, ResultadoFactura.agregada);
    expect(store.buscar('671'), isNotNull);
  });
}
