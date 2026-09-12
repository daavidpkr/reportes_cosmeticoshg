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
  ReviewableInvoice({required this.factura, required this.file})
      : customerKey = invoiceCustomerKey(factura);
  final Factura factura;
  final PreparedInvoiceXml file;
  String? vendedor;
  int? paymentTermDays;
  bool termEstablished = false;
  String customerKey;
  String? customerId;
  String? resolutionError;

  bool get customerAmbiguous => resolutionError != null;
}

String invoiceCustomerKey(Factura factura) {
  final identification = factura.identificacionComprador
      .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
      .toUpperCase();
  if (identification.isNotEmpty) return 'id:$identification';
  String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return 'legacy:${normalize(factura.cliente)}|${normalize(factura.nombreComercial)}';
}

class CustomerImportResolution {
  const CustomerImportResolution({
    required this.groupKey,
    required this.status,
    this.customerId,
    this.paymentTermDays,
    this.message,
  });

  final String groupKey;
  final String status;
  final String? customerId;
  final int? paymentTermDays;
  final String? message;

  factory CustomerImportResolution.fromJson(Map<String, dynamic> json) =>
      CustomerImportResolution(
        groupKey: json['group_key']?.toString() ?? '',
        status: json['status']?.toString() ?? 'ambiguous',
        customerId: json['customer_id']?.toString(),
        paymentTermDays: (json['payment_term_days'] as num?)?.toInt(),
        message: json['message']?.toString(),
      );
}

List<Map<String, String>> buildCustomerResolutionPayload(
    Iterable<ReviewableInvoice> invoices) {
  final unique = <String, ReviewableInvoice>{};
  for (final invoice in invoices) {
    unique.putIfAbsent(invoice.customerKey, () => invoice);
  }
  return unique.entries
      .map((entry) => {
            'group_key': entry.key,
            'identificacion_comprador':
                entry.value.factura.identificacionComprador,
            'tipo_identificacion_comprador':
                entry.value.factura.tipoIdentificacionComprador,
            'cliente': entry.value.factura.cliente,
            'nombre_comercial': entry.value.factura.nombreComercial,
          })
      .toList(growable: false);
}

void applyCustomerImportResolutions(
  Iterable<ReviewableInvoice> invoices,
  Iterable<CustomerImportResolution> resolutions,
) {
  final byInputKey = <String, CustomerImportResolution>{
    for (final resolution in resolutions) resolution.groupKey: resolution,
  };
  for (final invoice in invoices) {
    final resolution = byInputKey[invoice.customerKey];
    if (resolution == null) {
      invoice.resolutionError =
          'No se pudo resolver este cliente de forma segura.';
      continue;
    }
    if (resolution.status == 'ambiguous') {
      invoice.resolutionError = resolution.message ??
          'Hay más de un perfil compatible; revisa el cliente antes de importar.';
      continue;
    }
    invoice.customerId = resolution.customerId;
    if (resolution.customerId != null) {
      invoice.customerKey = 'customer:${resolution.customerId}';
    }
    invoice.paymentTermDays = resolution.paymentTermDays;
    invoice.termEstablished = resolution.paymentTermDays != null;
  }

  // Different input spellings can resolve to the same canonical customer.
  // Share one state across every invoice after canonical IDs are known.
  final canonical = <String, ReviewableInvoice>{};
  for (final invoice in invoices.where((item) => !item.customerAmbiguous)) {
    final first = canonical.putIfAbsent(invoice.customerKey, () => invoice);
    invoice.paymentTermDays = first.paymentTermDays;
    invoice.termEstablished = first.termEstablished;
  }
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
    invoices.sort((a, b) =>
        compareInvoiceReferences(a.factura.secuencial, b.factura.secuencial));
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

/// Numeric invoice order without losing the original, zero-padded reference.
/// Non-numeric references remain importable and are placed deterministically
/// after numeric references.
int compareInvoiceReferences(String left, String right) {
  final leftValue = BigInt.tryParse(left.trim());
  final rightValue = BigInt.tryParse(right.trim());
  if (leftValue != null && rightValue != null) {
    final numeric = leftValue.compareTo(rightValue);
    if (numeric != 0) return numeric;
  } else if (leftValue != null) {
    return -1;
  } else if (rightValue != null) {
    return 1;
  }
  return left.trim().compareTo(right.trim());
}
