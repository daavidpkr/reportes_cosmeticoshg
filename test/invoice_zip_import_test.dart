import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cosmeticos_hg_reportes/services/facturas_store.dart';
import 'package:cosmeticos_hg_reportes/services/invoice_batch_importer.dart';
import 'package:cosmeticos_hg_reportes/services/invoice_file_preparer.dart';
import 'package:cosmeticos_hg_reportes/screens/carga_facturas_screen.dart';
import 'package:cosmeticos_hg_reportes/services/vendedores_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _preparer = InvoiceFilePreparer();

String _xml(String reference, {String date = '19/08/2026'}) => '''
<factura>
  <razonSocialComprador>Cliente $reference</razonSocialComprador>
  <direccionComprador>Quito | Local $reference</direccionComprador>
  <fechaEmision>$date</fechaEmision>
  <secuencial>$reference</secuencial>
  <importeTotal>123.45</importeTotal>
</factura>
''';

String _xmlWithBuyerId(String reference, String buyerId, String buyerType) =>
    '''
<factura><razonSocialComprador>Cliente variable $reference</razonSocialComprador>
<direccionComprador>Quito | Comercial conservado</direccionComprador>
<identificacionComprador>$buyerId</identificacionComprador>
<tipoIdentificacionComprador>$buyerType</tipoIdentificacionComprador>
<fechaEmision>19/08/2026</fechaEmision><secuencial>$reference</secuencial>
<importeTotal>123.45</importeTotal></factura>''';

SelectedInvoiceFile _file(String name, List<int> bytes) =>
    SelectedInvoiceFile(name: name, bytes: Uint8List.fromList(bytes));

Uint8List _zip(Map<String, List<int>> files, {String? password}) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return ZipEncoder(password: password).encodeBytes(archive);
}

Future<InvoiceBatchImportResult> _import(
    PreparedInvoiceBatch batch, FacturasStore store,
    {void Function()? persisted}) {
  return const InvoiceBatchImporter().import(
    batch,
    store: store,
    persist: () async => persisted?.call(),
  );
}

void main() {
  group('preparación XML y ZIP', () {
    test('conserva uno y varios XML directos sin cambiar bytes ni nombres',
        () async {
      final first = utf8.encode(_xml('001'));
      final result = await _preparer.prepare([
        _file('uno.xml', first),
        _file('DOS.XML', utf8.encode(_xml('002'))),
      ]);
      expect(result.directXmlSelected, 2);
      expect(result.zipSelected, 0);
      expect(result.xmlFiles.map((file) => file.name), ['uno.xml', 'DOS.XML']);
      expect(result.xmlFiles.first.bytes, first);
      expect(result.issues, isEmpty);
    });

    test('ZIP ignora PDF y encuentra varios XML, carpetas y mayúsculas',
        () async {
      final result = await _preparer.prepare([
        _file(
            'facturas.zip',
            _zip({
              'factura.xml': utf8.encode(_xml('001')),
              'factura.pdf': [1, 2, 3],
              'carpeta/segunda.XML': utf8.encode(_xml('002')),
            })),
      ]);
      expect(result.zipSelected, 1);
      expect(result.xmlFoundInZips, 2);
      expect(result.xmlFiles.map((file) => file.name),
          ['factura.xml', 'segunda.XML']);
      expect(result.xmlFiles.every((file) => file.fromZip), isTrue);
    });

    test('admite varios ZIP y mezcla de XML y ZIP', () async {
      final result = await _preparer.prepare([
        _file('directo.xml', utf8.encode(_xml('001'))),
        _file('a.zip', _zip({'a.xml': utf8.encode(_xml('002'))})),
        _file('b.zip', _zip({'b.xml': utf8.encode(_xml('003'))})),
      ]);
      expect(result.directXmlSelected, 1);
      expect(result.zipSelected, 2);
      expect(result.xmlFoundInZips, 2);
      expect(result.xmlFiles, hasLength(3));
    });

    test('informa ZIP vacío, sin XML y dañado individualmente', () async {
      final result = await _preparer.prepare([
        _file('vacio.zip', _zip({})),
        _file(
            'pdf.zip',
            _zip({
              'factura.pdf': [1]
            })),
        _file('danado.zip', [1, 2, 3, 4]),
        _file('valido.xml', utf8.encode(_xml('001'))),
      ]);
      expect(result.xmlFiles, hasLength(1));
      expect(
          result.issues.map((issue) => issue.kind),
          containsAll([
            InvoiceFileIssueKind.emptyZip,
            InvoiceFileIssueKind.zipWithoutXml,
            InvoiceFileIssueKind.damagedZip,
          ]));
    });

    test('rechaza ZIP cifrado', () async {
      final result = await _preparer.prepare([
        _file(
            'cifrado.zip',
            _zip(
              {'factura.xml': utf8.encode(_xml('001'))},
              password: 'secreto',
            )),
      ]);
      expect(result.xmlFiles, isEmpty);
      expect(result.issues.single.kind, InvoiceFileIssueKind.encryptedZip);
    });

    test('protege contra ZIP Slip y rutas absolutas', () async {
      for (final name in [
        '../factura.xml',
        '/factura.xml',
        r'C:\factura.xml'
      ]) {
        final result = await _preparer.prepare([
          _file('inseguro.zip', _zip({name: utf8.encode(_xml('001'))})),
        ]);
        expect(result.xmlFiles, isEmpty);
        expect(result.issues.single.kind, InvoiceFileIssueKind.unsafeZip);
      }
    });

    test('aplica límites de ZIP, XML, entradas y expansión total', () async {
      const limits = InvoiceArchiveLimits(
        maxZipBytes: 10000,
        maxExpandedBytes: 20,
        maxXmlBytes: 15,
        maxEntries: 2,
      );
      const preparer = InvoiceFilePreparer(limits: limits);
      final expanded = await preparer.prepare([
        _file('grande.zip', _zip({'a.xml': List.filled(21, 65)})),
      ]);
      expect(expanded.issues.single.kind, InvoiceFileIssueKind.tooLarge);

      final entries = await preparer.prepare([
        _file(
            'muchos.zip',
            _zip({
              'a.txt': [1],
              'b.txt': [2],
              'c.txt': [3]
            })),
      ]);
      expect(entries.issues.single.kind, InvoiceFileIssueKind.tooLarge);

      final direct = await preparer.prepare([
        _file('grande.xml', List.filled(16, 65)),
      ]);
      expect(direct.issues.single.kind, InvoiceFileIssueKind.tooLarge);
    });
  });

  group('importador único', () {
    late FacturasStore store;
    setUp(() {
      store = FacturasStore.instance;
      store
        ..limpiar()
        ..mesPermitido = 8
        ..anioPermitido = 2026;
    });
    tearDown(() => store.limpiar());

    test('extrae identificación, tipo y ceros iniciales', () {
      final parsed = store
          .analizarTexto(_xmlWithBuyerId('000000656', ' 001-002 003 ', '04'));
      expect(parsed.factura!.identificacionComprador, '001002003');
      expect(parsed.factura!.tipoIdentificacionComprador, '04');
      expect(parsed.factura!.nombreComercial, 'Comercial conservado');
      expect(parsed.factura!.secuencial, '000000656');
    });

    test('XML directo, ZIP y mixto conservan la identidad de comprador',
        () async {
      final bytes = utf8.encode(_xmlWithBuyerId('001', '000123', '05'));
      final batch = await _preparer.prepare([
        _file('directo.xml', bytes),
        _file('lote.zip', _zip({'interno.xml': bytes})),
      ]);
      final review = const InvoiceBatchImporter().review(batch, store: store);
      expect(review.invoices, hasLength(1));
      expect(review.invoices.single.factura.identificacionComprador, '000123');
    });

    test('omite la misma referencia directa e interna', () async {
      final batch = await _preparer.prepare([
        _file('directa.xml', utf8.encode(_xml('001'))),
        _file('facturas.zip',
            _zip({'otra-nombre.xml': utf8.encode(_xml('001'))})),
      ]);
      var persists = 0;
      final result = await _import(batch, store, persisted: () => persists++);
      expect(result.imported, 1);
      expect(result.duplicates, 1);
      expect(store.cantidad, 1);
      expect(persists, 1);
    });

    test('XML inválido no impide importar los válidos del mismo lote',
        () async {
      final batch = await _preparer.prepare([
        _file(
            'facturas.zip',
            _zip({
              'invalido.xml': utf8.encode('<no-es-factura/>'),
              'valido.xml': utf8.encode(_xml('002')),
            })),
      ]);
      final result = await _import(batch, store);
      expect(result.imported, 1);
      expect(result.invalid, 1);
      expect(store.buscar('002'), isNotNull);
    });

    test('XML directo y extraído recorren el mismo importador y son idénticos',
        () async {
      final bytes = utf8.encode(_xml('000000656'));
      final directBatch =
          await _preparer.prepare([_file('factura.xml', bytes)]);
      await _import(directBatch, store);
      final direct = store.buscar('000000656')!;
      store.limpiar();

      final zipBatch = await _preparer.prepare([
        _file('factura.zip', _zip({'interna/factura.xml': bytes})),
      ]);
      await _import(zipBatch, store);
      final zipped = store.buscar('000000656')!;

      expect(zipped.toJson(), direct.toJson());
      expect(zipped.secuencial, '000000656');
      expect(store.buscar('656'), same(zipped));
    });

    test('solo persiste automáticamente cuando hay facturas válidas', () async {
      var persists = 0;
      final invalidBatch = await _preparer.prepare([
        _file('invalido.xml', utf8.encode('texto')),
      ]);
      await _import(invalidBatch, store, persisted: () => persists++);
      expect(persists, 0);

      final validBatch = await _preparer.prepare([
        _file('valido.xml', utf8.encode(_xml('003'))),
      ]);
      await _import(validBatch, store, persisted: () => persists++);
      expect(persists, 1);
    });

    test('fallo transaccional restaura la memoria sin lote parcial', () async {
      final batch = await _preparer.prepare([
        _file('valido.xml', utf8.encode(_xml('004'))),
      ]);
      await expectLater(
        _import(batch, store, persisted: () => throw Exception('rollback')),
        throwsException,
      );
      expect(store.buscar('004'), isNull);
    });

    test('revisión no escribe y separa duplicados, existentes e inválidos',
        () async {
      final batch = await _preparer.prepare([
        _file('uno.xml', utf8.encode(_xml('010'))),
        _file('repetido.xml', utf8.encode(_xml('010'))),
        _file('existente.xml', utf8.encode(_xml('011'))),
        _file('invalido.xml', utf8.encode('<otro/>')),
      ]);
      final review = const InvoiceBatchImporter()
          .review(batch, store: store, existingReferences: {'011'});
      expect(review.invoices.map((e) => e.factura.secuencial), ['010']);
      expect(
          review.issues.map((e) => e.kind),
          containsAll([
            InvoiceReviewIssueKind.duplicateSelection,
            InvoiceReviewIssueKind.alreadyExists,
            InvoiceReviewIssueKind.invalid,
          ]));
      expect(store.cantidad, 0);
    });

    test('ordena numéricamente XML directos y conserva ceros', () async {
      final batch = await _preparer.prepare([
        _file('13.xml', utf8.encode(_xml('000000013'))),
        _file('1.xml', utf8.encode(_xml('1'))),
        _file('11.xml', utf8.encode(_xml('000000011'))),
        _file('10.xml', utf8.encode(_xml('10'))),
        _file('2.xml', utf8.encode(_xml('2'))),
        _file('12.xml', utf8.encode(_xml('000000012'))),
      ]);
      final review = const InvoiceBatchImporter().review(batch, store: store);
      expect(review.invoices.map((e) => e.factura.secuencial),
          ['1', '2', '10', '000000011', '000000012', '000000013']);
    });

    test('ordena ZIP interno y deja referencias no numéricas al final',
        () async {
      final batch = await _preparer.prepare([
        _file(
            'desordenado.zip',
            _zip({
              '12.xml': utf8.encode(_xml('12')),
              'especial.xml': utf8.encode(_xml('A-1')),
              '13.xml': utf8.encode(_xml('13')),
              '11.xml': utf8.encode(_xml('11')),
            })),
      ]);
      final review = const InvoiceBatchImporter().review(batch, store: store);
      expect(review.invoices.map((e) => e.factura.secuencial),
          ['11', '12', '13', 'A-1']);
    });
  });

  group('resolución canónica de plazos', () {
    late FacturasStore store;

    setUp(() {
      store = FacturasStore.instance
        ..limpiar()
        ..mesPermitido = 8
        ..anioPermitido = 2026;
    });
    tearDown(() => store.limpiar());

    Future<InvoiceBatchReview> reviewFor(List<String> xml) async {
      final batch = await _preparer.prepare([
        for (var index = 0; index < xml.length; index++)
          _file('$index.xml', utf8.encode(xml[index])),
      ]);
      return const InvoiceBatchImporter().review(batch, store: store);
    }

    test('normaliza identificación conservando ceros para agrupar', () async {
      final review = await reviewFor([
        _xmlWithBuyerId('101', ' 000-123 ', '04'),
        _xmlWithBuyerId('102', '000123', '04'),
      ]);
      expect(review.invoices.map((item) => item.customerKey).toSet(),
          {'id:000123'});
      expect(buildCustomerResolutionPayload(review.invoices), hasLength(1));
    });

    test('cliente nuevo y existente sin plazo quedan pendientes', () async {
      final review = await reviewFor([
        _xmlWithBuyerId('103', 'NEW-1', '04'),
        _xmlWithBuyerId('104', 'OLD-1', '04'),
      ]);
      applyCustomerImportResolutions(review.invoices, const [
        CustomerImportResolution(groupKey: 'id:NEW1', status: 'new'),
        CustomerImportResolution(
            groupKey: 'id:OLD1',
            status: 'existing_without_term',
            customerId: 'customer-old'),
      ]);
      expect(review.invoices.every((item) => !item.termEstablished), isTrue);
      expect(review.invoices.every((item) => item.paymentTermDays == null),
          isTrue);
    });

    test('cliente existente conserva 60 días en todas sus facturas', () async {
      final review = await reviewFor([
        _xmlWithBuyerId('105', '001-002-003', '04'),
        _xmlWithBuyerId('106', '001002003', '04'),
      ]);
      applyCustomerImportResolutions(review.invoices, const [
        CustomerImportResolution(
            groupKey: 'id:001002003',
            status: 'existing_with_term',
            customerId: 'lorena-equivalent',
            paymentTermDays: 60),
      ]);
      expect(review.invoices.every((item) => item.termEstablished), isTrue);
      expect(review.invoices.map((item) => item.paymentTermDays), [60, 60]);
      expect(review.invoices.map((item) => item.customerKey).toSet(),
          {'customer:lorena-equivalent'});
    });

    test('customer_id canónico reúne entradas con nombres diferentes',
        () async {
      final review = await reviewFor([
        _xmlWithBuyerId('107', 'A-1', '04'),
        _xmlWithBuyerId('108', 'B-2', '04'),
      ]);
      applyCustomerImportResolutions(review.invoices, const [
        CustomerImportResolution(
            groupKey: 'id:A1',
            status: 'existing_with_term',
            customerId: 'canonical',
            paymentTermDays: 30),
        CustomerImportResolution(
            groupKey: 'id:B2',
            status: 'existing_with_term',
            customerId: 'canonical',
            paymentTermDays: 30),
      ]);
      expect(review.invoices.map((item) => item.customerKey).toSet(),
          {'customer:canonical'});
    });

    test('coincidencia ambigua no se asigna ni se habilita', () async {
      final review = await reviewFor([
        _xmlWithBuyerId('109', 'AMB-1', '04'),
      ]);
      applyCustomerImportResolutions(review.invoices, const [
        CustomerImportResolution(
            groupKey: 'id:AMB1',
            status: 'ambiguous',
            message: 'Dos perfiles históricos coinciden.'),
      ]);
      expect(review.invoices.single.customerAmbiguous, isTrue);
      expect(review.invoices.single.customerId, isNull);
    });
  });

  testWidgets('plazo existente no se solicita y permite confirmar',
      (tester) async {
    final store = FacturasStore.instance
      ..limpiar()
      ..mesPermitido = 8
      ..anioPermitido = 2026;
    addTearDown(store.limpiar);
    final batch = await _preparer.prepare([
      _file(
          'lorena.xml', utf8.encode(_xmlWithBuyerId('110', '001002003', '04'))),
    ]);
    final review = const InvoiceBatchImporter().review(batch, store: store);
    applyCustomerImportResolutions(review.invoices, const [
      CustomerImportResolution(
          groupKey: 'id:001002003',
          status: 'existing_with_term',
          customerId: 'lorena-equivalent',
          paymentTermDays: 60),
    ]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InvoiceReviewDialog(
      review: review,
      requirePaymentTerms: true,
      vendedores: const [Vendedor(codigo: '01', nombre: 'Ana')],
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Plazo configurado: 60 días'), findsOneWidget);
    expect(find.text('Días de pago obligatorios'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('assign-all-seller')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('01 - Ana').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('confirm-invoice-import')))
            .onPressed,
        isNotNull);
  });

  testWidgets('varias facturas sin plazo muestran un solo editor',
      (tester) async {
    final store = FacturasStore.instance
      ..limpiar()
      ..mesPermitido = 8
      ..anioPermitido = 2026;
    addTearDown(store.limpiar);
    final batch = await _preparer.prepare([
      _file('uno.xml', utf8.encode(_xmlWithBuyerId('111', 'NEW-2', '04'))),
      _file('dos.xml', utf8.encode(_xmlWithBuyerId('112', 'NEW-2', '04'))),
    ]);
    final review = const InvoiceBatchImporter().review(batch, store: store);
    applyCustomerImportResolutions(review.invoices, const [
      CustomerImportResolution(groupKey: 'id:NEW2', status: 'new'),
    ]);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InvoiceReviewDialog(
      review: review,
      requirePaymentTerms: true,
      vendedores: const [Vendedor(codigo: '01', nombre: 'Ana')],
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Días de pago obligatorios'), findsOneWidget);
    expect(find.textContaining('se asigna una sola vez'), findsOneWidget);
  });

  testWidgets('revisión exige vendedor, permite masivo y cambio individual',
      (tester) async {
    final store = FacturasStore.instance
      ..limpiar()
      ..mesPermitido = 8
      ..anioPermitido = 2026;
    final batch = await _preparer.prepare([
      _file('uno.xml', utf8.encode(_xml('021'))),
      _file('dos.xml', utf8.encode(_xml('022'))),
    ]);
    final review = const InvoiceBatchImporter().review(batch, store: store);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InvoiceReviewDialog(
      review: review,
      vendedores: const [
        Vendedor(codigo: '01', nombre: 'Ana'),
        Vendedor(codigo: '02', nombre: 'Luz'),
      ],
    ))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('confirm-invoice-import')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('assign-all-seller')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('01 - Ana').last);
    await tester.pumpAndSettle();
    expect(review.invoices.every((e) => e.vendedor == '01 - Ana'), isTrue);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('confirm-invoice-import')))
            .onPressed,
        isNotNull);
    tester
        .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('seller-022')))
        .onChanged!('02 - Luz');
    await tester.pumpAndSettle();
    expect(review.invoices.first.vendedor, '01 - Ana');
    expect(review.invoices.last.vendedor, '02 - Luz');
    expect(store.cantidad, 0);
  });
}
