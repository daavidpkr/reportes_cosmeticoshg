import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catalog.dart';

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
  Future<List<Catalog>> list({
    required int offset,
    required int limit,
    String query = '',
    CatalogFilter filter = CatalogFilter.all,
    bool includeAdministration = true,
  });
  Future<Uint8List> download(String path, {void Function(double)? onProgress});
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
  Future<Uint8List> download(String path,
      {void Function(double)? onProgress}) async {
    final signed =
        await _client.storage.from('catalogos').createSignedUrl(path, 300);
    final request = http.Request('GET', Uri.parse(signed));
    final response = await _http.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'No se pudo descargar el archivo (${response.statusCode}).');
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
    onProgress?.call(1);
    return bytes.takeBytes();
  }

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {
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
