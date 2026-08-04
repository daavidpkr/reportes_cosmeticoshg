import 'package:cosmeticos_hg_reportes/services/facturas_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final store = FacturasStore.instance;

  setUp(store.limpiar);

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
}
