import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catalog.dart';
import 'catalog_file_error.dart';

class CatalogDraft {
  const CatalogDraft({
    required this.id,
    required this.version,
    required this.filePath,
    required this.coverPath,
  });

  final String id;
  final int version;
  final String filePath;
  final String coverPath;
}

abstract class CatalogRepository {
  Future<Catalog?> getById(String id);
  Future<Catalog?> getFeatured();
  Future<List<Catalog>> list({
    required int offset,
    required int limit,
    String query = '',
    CatalogFilter filter = CatalogFilter.all,
    bool includeAdministration = true,
  });
  Future<Uint8List> download(
    String path, {
    void Function(double)? onProgress,
    bool requirePdf = false,
  });
  Future<void> upload(String path, Uint8List bytes, String contentType);
  Future<void> removeObjects(Iterable<String> paths);
  Future<CatalogDraft> createDraft(String title, int order);
  Future<Catalog> saveMetadata(Catalog catalog,
      {required String title, required int order});
  Future<Catalog> publish({
    required Catalog catalog,
    required String title,
    required String filePath,
    required String coverPath,
    required int pageCount,
    required bool replaceFile,
    required int order,
  });
  Future<Catalog> setFeatured(String id);
  Future<Catalog> setActive(String id, bool active);
  Future<void> deleteAfterStorage(String id, int expectedVersion);
}

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository({SupabaseClient? client, http.Client? httpClient})
      : _client = client ?? Supabase.instance.client,
        _http = httpClient ?? http.Client();

  final SupabaseClient _client;
  final http.Client _http;

  @override
  Future<Catalog?> getById(String id) async {
    final row = await _client
        .from('catalogos_con_etiquetas')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Catalog.fromJson(row);
  }

  @override
  Future<Catalog?> getFeatured() async {
    final row = await _client
        .from('catalogos_con_etiquetas')
        .select()
        .eq('estado', 'publicado')
        .eq('activo', true)
        .eq('destacado', true)
        .limit(1)
        .maybeSingle();
    return row == null ? null : Catalog.fromJson(row);
  }

  @override
  Future<List<Catalog>> list({
    required int offset,
    required int limit,
    String query = '',
    CatalogFilter filter = CatalogFilter.all,
    bool includeAdministration = true,
  }) async {
    dynamic request = _client.from('catalogos_con_etiquetas').select();
    if (!includeAdministration) {
      request = request.eq('estado', 'publicado').eq('activo', true);
    }
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      request = request.ilike('titulo', '%${_escapeLike(trimmed)}%');
    }
    if (filter == CatalogFilter.newItems) {
      request = request.eq('es_nuevo', true);
    }
    if (filter == CatalogFilter.updated) {
      request = request.eq('es_actualizado', true);
    }
    final rows = await request
        .order('destacado', ascending: false)
        .order('orden')
        .order('fecha_actualizacion', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(rows as List)
        .map(Catalog.fromJson)
        .toList(growable: false);
  }

  String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  @override
  Future<Uint8List> download(
    String path, {
    void Function(double)? onProgress,
    bool requirePdf = false,
  }) async {
    _validateStoragePath(path);
    late final String signed;
    try {
      signed =
          await _client.storage.from('catalogos').createSignedUrl(path, 300);
    } catch (error) {
      logCatalogFileError(CatalogFileStage.signedUrl, error);
      throw CatalogFileException(
        stage: CatalogFileStage.signedUrl,
        userMessage: 'Storage no pudo crear la URL firmada.',
        detail: sanitizeCatalogError(error),
      );
    }
    final signedUri = Uri.tryParse(signed);
    if (signedUri == null || !signedUri.hasScheme || signedUri.host.isEmpty) {
      throw const CatalogFileException(
        stage: CatalogFileStage.signedUrl,
        userMessage: 'Storage devolvió una URL firmada inválida.',
      );
    }
    late final http.StreamedResponse response;
    try {
      response = await _http.send(http.Request('GET', signedUri));
    } catch (error) {
      logCatalogFileError(CatalogFileStage.httpDownload, error);
      throw CatalogFileException(
        stage: CatalogFileStage.httpDownload,
        userMessage:
            'No se pudo conectar con el archivo. Revisa la conexión e inténtalo nuevamente.',
        detail: sanitizeCatalogError(error),
      );
    }
    final bytes = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.stream) {
      bytes.add(chunk);
      received += chunk.length;
      if (response.contentLength case final total? when total > 0) {
        onProgress?.call(received / total);
      }
    }
    final result = bytes.takeBytes();
    final contentType =
        response.headers['content-type']?.split(';').first.trim().toLowerCase();
    final contentLength = response.contentLength;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final serverMessage = _serverErrorMessage(result);
      final error = CatalogFileException(
        stage: CatalogFileStage.httpDownload,
        httpStatus: response.statusCode,
        userMessage:
            'Storage no pudo entregar el archivo (HTTP ${response.statusCode})${serverMessage == null ? '.' : ': $serverMessage'}',
        detail: 'content-type=${contentType ?? 'ausente'}',
      );
      logCatalogFileError(CatalogFileStage.httpDownload, error,
          httpStatus: response.statusCode);
      throw error;
    }
    onProgress?.call(1);
    if (contentLength != null && contentLength != result.length) {
      final error = CatalogFileException(
        stage: CatalogFileStage.validation,
        httpStatus: response.statusCode,
        userMessage:
            'La descarga quedó incompleta: se esperaban $contentLength bytes y llegaron ${result.length}.',
        detail: 'content-type=${contentType ?? 'ausente'}',
      );
      logCatalogFileError(CatalogFileStage.validation, error,
          httpStatus: response.statusCode);
      throw error;
    }
    if (requirePdf) {
      _validatePdfResponse(
        result,
        status: response.statusCode,
        contentType: contentType,
        contentLength: contentLength,
      );
    } else if (result.isEmpty) {
      throw CatalogFileException(
        stage: CatalogFileStage.validation,
        httpStatus: response.statusCode,
        userMessage: 'Storage entregó un archivo vacío.',
        detail: 'content-type=${contentType ?? 'ausente'}',
      );
    }
    return result;
  }

  void _validateStoragePath(String path) {
    final uri = Uri.tryParse(path);
    final segments = path.split('/');
    final valid = path == path.trim() &&
        uri != null &&
        !uri.hasScheme &&
        uri.host.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty &&
        !path.startsWith('/') &&
        !path.contains(r'\') &&
        segments.length >= 4 &&
        segments.first != 'catalogos' &&
        !segments.any((part) => part.isEmpty || part == '.' || part == '..');
    if (!valid) {
      throw const CatalogFileException(
        stage: CatalogFileStage.metadata,
        userMessage:
            'La ruta del archivo no es una ruta relativa válida del bucket catalogos.',
      );
    }
  }

  void _validatePdfResponse(
    Uint8List bytes, {
    required int status,
    required String? contentType,
    required int? contentLength,
  }) {
    String? message;
    if (bytes.isEmpty || contentLength == 0) {
      message = 'El PDF publicado está vacío.';
    } else if (contentType != 'application/pdf') {
      message =
          'Storage respondió ${contentType ?? 'sin Content-Type'} en lugar de application/pdf.';
    } else if (!isValidPdfBytes(bytes)) {
      message = 'La respuesta no comienza con la cabecera %PDF-.';
    }
    if (message == null) return;
    final error = CatalogFileException(
      stage: CatalogFileStage.validation,
      httpStatus: status,
      userMessage: message,
      detail:
          'content-type=${contentType ?? 'ausente'}, content-length=${contentLength ?? 'ausente'}, bytes=${bytes.length}',
    );
    logCatalogFileError(CatalogFileStage.validation, error, httpStatus: status);
    throw error;
  }

  String? _serverErrorMessage(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final decoded = String.fromCharCodes(bytes.take(512)).trim();
    if (decoded.isEmpty) return null;
    return sanitizeCatalogError(decoded);
  }

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {
    if (contentType == 'application/pdf' && !isValidPdfBytes(bytes)) {
      throw const CatalogFileException(
        stage: CatalogFileStage.validation,
        userMessage: 'El PDF está vacío o no es válido.',
      );
    }
    if (bytes.isEmpty) {
      throw const CatalogFileException(
        stage: CatalogFileStage.validation,
        userMessage: 'El archivo que se intenta subir está vacío.',
      );
    }
    await _client.storage.from('catalogos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
  }

  @override
  Future<void> removeObjects(Iterable<String> paths) async {
    final existing = paths.where((path) => path.trim().isNotEmpty).toList();
    if (existing.isNotEmpty) {
      await _client.storage.from('catalogos').remove(existing);
    }
  }

  @override
  Future<CatalogDraft> createDraft(String title, int order) async {
    final result = await _client.rpc('admin_create_catalog_draft', params: {
      'p_titulo': title,
      'p_orden': order,
    });
    final row = Map<String, dynamic>.from((result as List).single as Map);
    return CatalogDraft(
      id: row['catalogo_id'].toString(),
      version: (row['version_actual'] as num).toInt(),
      filePath: row['archivo_path_esperado'].toString(),
      coverPath: row['portada_path_esperada'].toString(),
    );
  }

  @override
  Future<Catalog> saveMetadata(Catalog catalog,
          {required String title, required int order}) =>
      _publishRpc(catalog.id, title, null, null, null, false, order);

  @override
  Future<Catalog> publish({
    required Catalog catalog,
    required String title,
    required String filePath,
    required String coverPath,
    required int pageCount,
    required bool replaceFile,
    required int order,
  }) =>
      _publishRpc(catalog.id, title, filePath, coverPath, pageCount,
          replaceFile, order);

  Future<Catalog> _publishRpc(
    String id,
    String title,
    String? filePath,
    String? coverPath,
    int? pages,
    bool replace,
    int order,
  ) async {
    final result = await _client.rpc('admin_publish_catalog', params: {
      'p_catalogo_id': id,
      'p_titulo': title,
      'p_archivo_path': filePath,
      'p_portada_path': coverPath,
      'p_numero_paginas': pages,
      'p_reemplazar_archivo': replace,
      'p_orden': order,
    });
    return Catalog.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<Catalog> setFeatured(String id) async => Catalog.fromJson(
        Map<String, dynamic>.from(await _client.rpc(
          'admin_set_featured_catalog',
          params: {'p_catalogo_id': id},
        ) as Map),
      );

  @override
  Future<Catalog> setActive(String id, bool active) async => Catalog.fromJson(
        Map<String, dynamic>.from(await _client.rpc(
          'admin_set_catalog_active',
          params: {'p_catalogo_id': id, 'p_activo': active},
        ) as Map),
      );

  @override
  Future<void> deleteAfterStorage(String id, int expectedVersion) async {
    final deleted = await _client.rpc(
      'admin_delete_catalog_after_storage_cleanup',
      params: {
        'p_catalogo_id': id,
        'p_expected_version': expectedVersion,
        'p_storage_objects_deleted': true,
      },
    );
    if (deleted != true) throw StateError('El catálogo no se eliminó.');
  }
}
