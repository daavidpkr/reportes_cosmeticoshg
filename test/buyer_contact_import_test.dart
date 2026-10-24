import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cosmeticos_hg_reportes/services/facturas_store.dart';
import 'package:cosmeticos_hg_reportes/services/invoice_batch_importer.dart';
import 'package:cosmeticos_hg_reportes/services/invoice_file_preparer.dart';
import 'package:cosmeticos_hg_reportes/services/supabase_reportes_service.dart';
import 'package:flutter_test/flutter_test.dart';

String _invoice(
  String reference, {
  String address = 'Av. Siempre Viva 123 | Tienda Central',
  String extra = '',
  String buyerId = '0010020030001',
}) =>
    '''
<factura>
  <infoTributaria><razonSocial>EMISOR</razonSocial><telefono>022222222</telefono></infoTributaria>
  <razonSocialComprador>Comprador</razonSocialComprador>
  <identificacionComprador>$buyerId</identificacionComprador>
  <direccionComprador>$address</direccionComprador>
  <fechaEmision>24/10/2026</fechaEmision>
  <secuencial>$reference</secuencial><importeTotal>10.50</importeTotal>
  <infoAdicional>
    <campoAdicional nombre="Asesor">Vendedor 0999999999</campoAdicional>
    $extra
  </infoAdicional>
</factura>
''';

SelectedInvoiceFile _file(String name, List<int> bytes) =>
    SelectedInvoiceFile(name: name, bytes: Uint8List.fromList(bytes));

Uint8List _zip(String name, String xml) {
  final archive = Archive()..addFile(ArchiveFile.string(name, xml));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  late FacturasStore store;

  setUp(() {
    store = FacturasStore.instance
      ..limpiar()
      ..mesPermitido = 10
      ..anioPermitido = 2026;
  });
  tearDown(() => store.limpiar());

  test('separa dirección y nombre comercial sin cambiar la regla existente',
      () {
    final invoice = store.analizarTexto(_invoice('1')).factura!;
    expect(invoice.direccionComprador, 'Av. Siempre Viva 123');
    expect(invoice.nombreComercial, 'Tienda Central');
  });

  test('normaliza variantes de teléfono y correo y descarta inválidos', () {
    final invoice = store.analizarTexto(_invoice('2', extra: '''
      <campoAdicional nombre=" TELÉ FONO ">(+593) 99-123-4567</campoAdicional>
      <campoAdicional nombre="E-MAIL"> Ventas@Ejemplo.COM </campoAdicional>
    ''')).factura!;
    expect(invoice.telefonoComprador, '+593991234567');
    expect(invoice.correoComprador, 'ventas@ejemplo.com');

    final invalid = store.analizarTexto(_invoice('3', extra: '''
      <campoAdicional nombre="celular">sin número</campoAdicional>
      <campoAdicional nombre="correo">correo-inválido</campoAdicional>
    ''')).factura!;
    expect(invalid.telefonoComprador, isEmpty);
    expect(invalid.correoComprador, isEmpty);
  });

  test('acepta telefono, celular, email y correo sin usar emisor o asesor', () {
    final variants = {
      'teléfono': '0991112222',
      'telefono': '0991112222',
      'celular': '0991112222',
      'email': 'cliente@ejemplo.com',
      'e-mail': 'cliente@ejemplo.com',
      'correo': 'cliente@ejemplo.com',
    };
    for (final entry in variants.entries) {
      final invoice = store
          .analizarTexto(_invoice('4',
              extra:
                  '<campoAdicional nombre="${entry.key}">${entry.value}</campoAdicional>'))
          .factura!;
      if (entry.value.contains('@')) {
        expect(invoice.correoComprador, entry.value);
        expect(invoice.telefonoComprador, isEmpty);
      } else {
        expect(invoice.telefonoComprador, entry.value);
        expect(invoice.correoComprador, isEmpty);
      }
    }
  });

  test('XML, ZIP y lote mixto conservan la misma evidencia de contacto',
      () async {
    const preparer = InvoiceFilePreparer();
    final xml1 = _invoice('10', extra: '''
      <campoAdicional nombre="Celular">0991112222</campoAdicional>
      <campoAdicional nombre="Correo">uno@ejemplo.com</campoAdicional>''');
    final xml2 = _invoice('11', extra: '''
      <campoAdicional nombre="Teléfono">0981112222</campoAdicional>
      <campoAdicional nombre="Email">dos@ejemplo.com</campoAdicional>''');
    final batch = await preparer.prepare([
      _file('directa.xml', utf8.encode(xml1)),
      _file('lote.zip', _zip('interna.xml', xml2)),
    ]);
    final review = const InvoiceBatchImporter().review(batch, store: store);
    expect(review.invoices, hasLength(2));
    expect(review.invoices[0].factura.telefonoComprador, '0991112222');
    expect(review.invoices[0].factura.correoComprador, 'uno@ejemplo.com');
    expect(review.invoices[1].factura.telefonoComprador, '0981112222');
    expect(review.invoices[1].factura.correoComprador, 'dos@ejemplo.com');
  });

  test('payload conserva evidencia e identidad sin exponerla en presentación',
      () {
    final invoice = store
        .analizarTexto(_invoice('20', extra: '''
      <campoAdicional nombre="celular">0991112222</campoAdicional>
      <campoAdicional nombre="correo">cliente@ejemplo.com</campoAdicional>'''))
        .factura!;
    final payload = construirParametrosImportarFacturas(
      facturas: [invoice],
      anio: 2026,
      mes: 10,
      requestId: '00000000-0000-0000-0000-000000000001',
    )['p_invoices'] as List;
    expect(payload.single,
        containsPair('direccion_comprador', 'Av. Siempre Viva 123'));
    expect(payload.single, containsPair('telefono_comprador', '0991112222'));
    expect(payload.single,
        containsPair('correo_comprador', 'cliente@ejemplo.com'));
    expect(payload.single,
        containsPair('identificacion_comprador', '0010020030001'));
  });
}
