import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cosmeticos_hg_reportes/services/facturas_store.dart';
import 'package:cosmeticos_hg_reportes/services/invoice_batch_importer.dart';
import 'package:cosmeticos_hg_reportes/services/invoice_file_preparer.dart';
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
  });
}
