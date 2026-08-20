import 'dart:convert';

import 'facturas_store.dart';
import 'invoice_file_preparer.dart';

class InvoiceBatchImportResult {
  const InvoiceBatchImportResult({
    required this.imported,
    required this.duplicates,
    required this.invalid,
    required this.wrongMonth,
  });

  final int imported;
  final int duplicates;
  final int invalid;
  final int wrongMonth;
}

class InvoiceBatchImporter {
  const InvoiceBatchImporter();

  Future<InvoiceBatchImportResult> import(
    PreparedInvoiceBatch batch, {
    required FacturasStore store,
    required Future<void> Function() persist,
  }) async {
    var imported = 0;
    var duplicates = 0;
    var invalid = 0;
    var wrongMonth = 0;
    final references = <String>{};

    for (final file in batch.xmlFiles) {
      try {
        final text = utf8.decode(file.bytes, allowMalformed: true);
        final reference = store.referenciaDesdeTexto(text)?.trim();
        if (reference != null &&
            reference.isNotEmpty &&
            !references.add(reference)) {
          duplicates++;
          continue;
        }
        switch (store.agregarDesdeTexto(text)) {
          case ResultadoFactura.agregada:
            imported++;
          case ResultadoFactura.mesIncorrecto:
            wrongMonth++;
          case ResultadoFactura.invalida:
            invalid++;
        }
      } catch (_) {
        invalid++;
      }
    }
    if (imported > 0) await persist();
    return InvoiceBatchImportResult(
      imported: imported,
      duplicates: duplicates,
      invalid: invalid,
      wrongMonth: wrongMonth,
    );
  }
}
