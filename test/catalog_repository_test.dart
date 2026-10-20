import 'dart:convert';

import 'package:cosmeticos_hg_reportes/models/catalog.dart';
import 'package:cosmeticos_hg_reportes/services/catalog_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> catalogJson() => {
      'id': '00000000-0000-0000-0000-000000000001',
      'organization_id': '00000000-0000-0000-0000-000000000002',
      'titulo': 'Catálogo',
      'archivo_path': null,
      'portada_path': null,
      'version': 1,
      'numero_paginas': null,
      'estado': 'borrador',
      'activo': true,
      'destacado': false,
      'orden': 2,
      'created_at': '2026-10-19T12:00:00Z',
      'updated_at': '2026-10-19T12:00:00Z',
    };

void main() {
  test('usa las firmas RPC reales para crear, administrar y eliminar',
      () async {
    final calls = <String, Map<String, dynamic>>{};
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      accessToken: () async => 'token',
      httpClient: MockClient((request) async {
        final function = request.url.pathSegments.last;
        calls[function] = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map<String, dynamic>);
        final Object response = switch (function) {
          'admin_create_catalog_draft' => [
              {
                'catalogo_id': catalogJson()['id'],
                'version_actual': 1,
                'archivo_path_esperado':
                    '${catalogJson()['organization_id']}/${catalogJson()['id']}/v1/catalogo.pdf',
                'portada_path_esperada':
                    '${catalogJson()['organization_id']}/${catalogJson()['id']}/v1/portada.webp',
              }
            ],
          'admin_delete_catalog_after_storage_cleanup' => true,
          _ => catalogJson(),
        };
        return http.Response(jsonEncode(response), 200,
            headers: {'content-type': 'application/json'}, request: request);
      }),
    );
    final repository = SupabaseCatalogRepository(client: client);
    final draft = await repository.createDraft('Catálogo', 2);
    final catalog = Catalog.fromJson(catalogJson());
    await repository.saveMetadata(catalog, title: 'Nuevo título', order: 4);
    await repository.setFeatured(catalog.id);
    await repository.setActive(catalog.id, false);
    await repository.deleteAfterStorage(catalog.id, 1);

    expect(draft.version, 1);
    expect(calls['admin_create_catalog_draft'], {
      'p_titulo': 'Catálogo',
      'p_orden': 2,
    });
    expect(calls['admin_publish_catalog'],
        containsPair('p_reemplazar_archivo', false));
    expect(
        calls['admin_publish_catalog'], containsPair('p_archivo_path', null));
    expect(calls['admin_set_featured_catalog'], {'p_catalogo_id': catalog.id});
    expect(calls['admin_set_catalog_active'], {
      'p_catalogo_id': catalog.id,
      'p_activo': false,
    });
    expect(calls['admin_delete_catalog_after_storage_cleanup'], {
      'p_catalogo_id': catalog.id,
      'p_expected_version': 1,
      'p_storage_objects_deleted': true,
    });
    client.dispose();
  });
}
