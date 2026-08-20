import 'dart:typed_data';

import 'package:archive/archive.dart';

class InvoiceArchiveLimits {
  const InvoiceArchiveLimits({
    this.maxZipBytes = 25 * 1024 * 1024,
    this.maxExpandedBytes = 100 * 1024 * 1024,
    this.maxXmlBytes = 10 * 1024 * 1024,
    this.maxEntries = 1000,
  });

  final int maxZipBytes;
  final int maxExpandedBytes;
  final int maxXmlBytes;
  final int maxEntries;
}

class SelectedInvoiceFile {
  const SelectedInvoiceFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class PreparedInvoiceXml {
  const PreparedInvoiceXml({
    required this.name,
    required this.bytes,
    required this.fromZip,
  });

  final String name;
  final Uint8List bytes;
  final bool fromZip;
}

enum InvoiceFileIssueKind {
  unsupported,
  tooLarge,
  damagedZip,
  encryptedZip,
  emptyZip,
  zipWithoutXml,
  unsafeZip,
  extractionError,
}

class InvoiceFileIssue {
  const InvoiceFileIssue(this.fileName, this.kind, this.message);

  final String fileName;
  final InvoiceFileIssueKind kind;
  final String message;
}

class PreparedInvoiceBatch {
  const PreparedInvoiceBatch({
    required this.xmlFiles,
    required this.issues,
    required this.directXmlSelected,
    required this.zipSelected,
    required this.xmlFoundInZips,
  });

  final List<PreparedInvoiceXml> xmlFiles;
  final List<InvoiceFileIssue> issues;
  final int directXmlSelected;
  final int zipSelected;
  final int xmlFoundInZips;
}

class InvoiceFilePreparer {
  const InvoiceFilePreparer({
    this.limits = const InvoiceArchiveLimits(),
  });

  final InvoiceArchiveLimits limits;

  Future<PreparedInvoiceBatch> prepare(
    Iterable<SelectedInvoiceFile> selected,
  ) async {
    final xmlFiles = <PreparedInvoiceXml>[];
    final issues = <InvoiceFileIssue>[];
    var directXmlSelected = 0;
    var zipSelected = 0;
    var xmlFoundInZips = 0;

    for (final file in selected) {
      final lowerName = file.name.toLowerCase();
      if (lowerName.endsWith('.xml')) {
        directXmlSelected++;
        if (file.bytes.length > limits.maxXmlBytes) {
          issues.add(InvoiceFileIssue(
            file.name,
            InvoiceFileIssueKind.tooLarge,
            'El XML supera el límite permitido.',
          ));
        } else {
          xmlFiles.add(PreparedInvoiceXml(
            name: file.name,
            bytes: file.bytes,
            fromZip: false,
          ));
        }
        continue;
      }
      if (!lowerName.endsWith('.zip')) {
        issues.add(InvoiceFileIssue(
          file.name,
          InvoiceFileIssueKind.unsupported,
          'Solo se admiten archivos XML y ZIP.',
        ));
        continue;
      }

      zipSelected++;
      final extracted = _extractZip(file);
      issues.addAll(extracted.issues);
      xmlFoundInZips += extracted.xmlFiles.length;
      xmlFiles.addAll(extracted.xmlFiles);
    }

    return PreparedInvoiceBatch(
      xmlFiles: xmlFiles,
      issues: issues,
      directXmlSelected: directXmlSelected,
      zipSelected: zipSelected,
      xmlFoundInZips: xmlFoundInZips,
    );
  }

  _ZipExtraction _extractZip(SelectedInvoiceFile file) {
    if (file.bytes.length > limits.maxZipBytes) {
      return _ZipExtraction.issue(file.name, InvoiceFileIssueKind.tooLarge,
          'El ZIP supera el límite permitido.');
    }
    if (!_hasZipSignature(file.bytes)) {
      return _ZipExtraction.issue(file.name, InvoiceFileIssueKind.damagedZip,
          'El ZIP está dañado o no es válido.');
    }
    if (_hasEncryptedEntries(file.bytes)) {
      return _ZipExtraction.issue(file.name, InvoiceFileIssueKind.encryptedZip,
          'El ZIP está protegido con contraseña.');
    }

    Archive? archive;
    try {
      archive = ZipDecoder().decodeBytes(file.bytes, verify: true);
      if (archive.isEmpty) {
        return _ZipExtraction.issue(
            file.name, InvoiceFileIssueKind.emptyZip, 'El ZIP está vacío.');
      }
      if (archive.length > limits.maxEntries) {
        return _ZipExtraction.issue(file.name, InvoiceFileIssueKind.tooLarge,
            'El ZIP contiene demasiadas entradas.');
      }

      var expandedBytes = 0;
      for (final entry in archive) {
        if (!_isSafeRelativePath(entry.name) || entry.isSymbolicLink) {
          return _ZipExtraction.issue(file.name, InvoiceFileIssueKind.unsafeZip,
              'El ZIP contiene rutas inseguras.');
        }
        if (!entry.isFile) continue;
        expandedBytes += entry.size;
        if (entry.size < 0 || expandedBytes > limits.maxExpandedBytes) {
          return _ZipExtraction.issue(file.name, InvoiceFileIssueKind.tooLarge,
              'El contenido descomprimido supera el límite permitido.');
        }
      }

      final xmlFiles = <PreparedInvoiceXml>[];
      for (final entry in archive) {
        if (!entry.isFile || !entry.name.toLowerCase().endsWith('.xml')) {
          continue;
        }
        if (entry.size > limits.maxXmlBytes) {
          return _ZipExtraction.issue(file.name, InvoiceFileIssueKind.tooLarge,
              'Un XML del ZIP supera el límite permitido.');
        }
        try {
          final bytes = entry.readBytes();
          if (bytes == null || bytes.length > limits.maxXmlBytes) {
            return _ZipExtraction.issue(
                file.name,
                InvoiceFileIssueKind.tooLarge,
                'Un XML del ZIP supera el límite permitido.');
          }
          xmlFiles.add(PreparedInvoiceXml(
            name: _displayName(entry.name),
            bytes: bytes,
            fromZip: true,
          ));
        } catch (error) {
          final encrypted = _looksEncrypted(error);
          return _ZipExtraction.issue(
            file.name,
            encrypted
                ? InvoiceFileIssueKind.encryptedZip
                : InvoiceFileIssueKind.extractionError,
            encrypted
                ? 'El ZIP está protegido con contraseña.'
                : 'No se pudo extraer el ZIP.',
          );
        }
      }
      if (xmlFiles.isEmpty) {
        return _ZipExtraction.issue(file.name,
            InvoiceFileIssueKind.zipWithoutXml, 'El ZIP no contiene XML.');
      }
      return _ZipExtraction(xmlFiles, const []);
    } catch (error) {
      final encrypted = _looksEncrypted(error);
      return _ZipExtraction.issue(
        file.name,
        encrypted
            ? InvoiceFileIssueKind.encryptedZip
            : InvoiceFileIssueKind.damagedZip,
        encrypted
            ? 'El ZIP está protegido con contraseña.'
            : 'El ZIP está dañado o no es válido.',
      );
    } finally {
      archive?.clearSync();
    }
  }

  bool _isSafeRelativePath(String name) {
    final normalized = name.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) {
      return false;
    }
    var depth = 0;
    for (final part in normalized.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        depth--;
        if (depth < 0) return false;
      } else {
        depth++;
      }
    }
    return true;
  }

  String _displayName(String name) =>
      name.replaceAll('\\', '/').split('/').last;

  bool _looksEncrypted(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('password') ||
        text.contains('encrypt') ||
        text.contains('authentication');
  }

  bool _hasZipSignature(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) return false;
    return (bytes[2] == 0x03 && bytes[3] == 0x04) ||
        (bytes[2] == 0x05 && bytes[3] == 0x06) ||
        (bytes[2] == 0x07 && bytes[3] == 0x08);
  }

  bool _hasEncryptedEntries(Uint8List bytes) {
    for (var i = 0; i + 9 < bytes.length; i++) {
      if (bytes[i] != 0x50 || bytes[i + 1] != 0x4b) continue;
      final isLocal = bytes[i + 2] == 0x03 && bytes[i + 3] == 0x04;
      final isCentral = bytes[i + 2] == 0x01 && bytes[i + 3] == 0x02;
      if (!isLocal && !isCentral) continue;
      final flagOffset = i + (isLocal ? 6 : 8);
      final flags = bytes[flagOffset] | (bytes[flagOffset + 1] << 8);
      if ((flags & 1) != 0) return true;
    }
    return false;
  }
}

class _ZipExtraction {
  const _ZipExtraction(this.xmlFiles, this.issues);

  factory _ZipExtraction.issue(
          String name, InvoiceFileIssueKind kind, String message) =>
      _ZipExtraction(const [], [InvoiceFileIssue(name, kind, message)]);

  final List<PreparedInvoiceXml> xmlFiles;
  final List<InvoiceFileIssue> issues;
}
