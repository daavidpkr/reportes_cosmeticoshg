import 'dart:convert';

import '../models/factura.dart';
import 'facturas_store.dart';
import 'invoice_file_preparer.dart';

enum InvoiceReviewIssueKind {
  duplicateSelection,
  alreadyExists,
  invalid,
  wrongMonth
}

class InvoiceReviewIssue {
  const InvoiceReviewIssue(this.fileName, this.kind, this.message);
  final String fileName;
  final InvoiceReviewIssueKind kind;
  final String message;
}

class ReviewableInvoice {
  ReviewableInvoice({required this.factura, required this.file});
  final Factura factura;
  final PreparedInvoiceXml file;
  String? vendedor;
}

class InvoiceBatchReview {
  const InvoiceBatchReview(
      {required this.invoices, required this.issues, required this.fileIssues});
  final List<ReviewableInvoice> invoices;
  final List<InvoiceReviewIssue> issues;
  final List<InvoiceFileIssue> fileIssues;
}

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

  InvoiceBatchReview review(
    PreparedInvoiceBatch batch, {
    required FacturasStore store,
    Set<String> existingReferences = const {},
  }) {
    final invoices = <ReviewableInvoice>[];
    final issues = <InvoiceReviewIssue>[];
    final references = <String>{};
    for (final file in batch.xmlFiles) {
      try {
        final text = utf8.decode(file.bytes, allowMalformed: true);
        final parsed = store.analizarTexto(text);
        if (parsed.resultado != ResultadoFactura.agregada) {
          final wrongMonth = parsed.resultado == ResultadoFactura.mesIncorrecto;
          issues.add(InvoiceReviewIssue(
              file.name,
              wrongMonth
                  ? InvoiceReviewIssueKind.wrongMonth
                  : InvoiceReviewIssueKind.invalid,
              wrongMonth
                  ? 'La factura corresponde a otro mes.'
                  : 'El XML no es una factura válida.'));
          continue;
        }
        final factura = parsed.factura!;
        if (!references.add(factura.secuencial.trim())) {
          issues.add(InvoiceReviewIssue(
              file.name,
              InvoiceReviewIssueKind.duplicateSelection,
              'Referencia duplicada dentro de la selección.'));
        } else if (existingReferences.contains(factura.secuencial.trim())) {
          issues.add(InvoiceReviewIssue(
              file.name,
              InvoiceReviewIssueKind.alreadyExists,
              'La factura ya existe en el reporte.'));
        } else {
          invoices.add(ReviewableInvoice(factura: factura, file: file));
        }
      } catch (_) {
        issues.add(InvoiceReviewIssue(file.name, InvoiceReviewIssueKind.invalid,
            'No se pudo leer el XML.'));
      }
    }
    return InvoiceBatchReview(
        invoices: invoices, issues: issues, fileIssues: batch.issues);
  }

  Future<InvoiceBatchImportResult> import(
    PreparedInvoiceBatch batch, {
    required FacturasStore store,
    required Future<void> Function() persist,
  }) async {
    final snapshot = store.facturas;
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
    if (imported > 0) {
      try {
        await persist();
      } catch (_) {
        store.cargar(snapshot);
        rethrow;
      }
    }
    return InvoiceBatchImportResult(
      imported: imported,
      duplicates: duplicates,
      invalid: invalid,
      wrongMonth: wrongMonth,
    );
  }
}
