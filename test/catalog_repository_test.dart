import 'dart:convert';
import 'dart:typed_data';

import 'package:cosmeticos_hg_reportes/models/catalog.dart';
import 'package:cosmeticos_hg_reportes/services/catalog_file_error.dart';
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
  test('consulta el destacado publicado y activo independientemente', () async {
    Uri? requestedUri;
    final featuredRow = {
      ...catalogJson(),
      'estado': 'publicado',
      'activo': true,
      'destacado': true,
      'archivo_path':
          '${catalogJson()['organization_id']}/${catalogJson()['id']}/v1/catalogo.pdf',
      'portada_path':
          '${catalogJson()['organization_id']}/${catalogJson()['id']}/v1/portada.webp',
      'numero_paginas': 1,
      'fecha_publicacion': '2026-10-19T12:00:00Z',
      'fecha_actualizacion': '2026-10-19T12:00:00Z',
    };
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      accessToken: () async => 'session-token',
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode(featuredRow),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    final featured = await SupabaseCatalogRepository(
      client: client,
      queryContextProvider: () async => (
        userId: 'user',
        organizationId: catalogJson()['organization_id']! as String,
      ),
    ).getFeatured();

    expect(featured?.featured, isTrue);
    expect(requestedUri?.queryParameters['estado'], 'eq.publicado');
    expect(requestedUri?.queryParameters['activo'], 'eq.true');
    expect(requestedUri?.queryParameters['destacado'], 'eq.true');
    expect(requestedUri?.queryParameters['limit'], '1');
    expect(requestedUri?.queryParameters, isNot(contains('offset')));
  });

  test('confirma dos veces un destacado ausente en el mismo contexto',
      () async {
    var catalogRequests = 0;
    var contextRequests = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      accessToken: () async => 'session-token',
      httpClient: MockClient((request) async {
        catalogRequests++;
        return http.Response(
          'null',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    final repository = SupabaseCatalogRepository(
      client: client,
      queryContextProvider: () async {
        contextRequests++;
        return (userId: 'user', organizationId: 'organization');
      },
    );

    expect(await repository.getFeatured(), isNull);
    expect(catalogRequests, 2);
    expect(contextRequests, 3);
  });

  test('rechaza un null si cambia la sesión u organización', () async {
    var contextRequests = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      accessToken: () async => 'session-token',
      httpClient: MockClient((request) async => http.Response(
            'null',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          )),
    );
    addTearDown(client.dispose);
    final repository = SupabaseCatalogRepository(
      client: client,
      queryContextProvider: () async => (
        userId: 'user',
        organizationId:
            contextRequests++ == 0 ? 'organization-a' : 'organization-b',
      ),
    );

    await expectLater(repository.getFeatured(), throwsStateError);
  });

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

  group('descarga privada', () {
    late SupabaseClient client;

    tearDown(() => client.dispose());

    SupabaseCatalogRepository repositoryFor(http.Client downloadClient) {
      client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        accessToken: () async => 'session-token',
        httpClient: MockClient((request) async {
          expect(
              request.url.path, contains('/storage/v1/object/sign/catalogos/'));
          expect(request.headers['authorization'], 'Bearer session-token');
          return http.Response(
            jsonEncode(
                {'signedURL': '/object/sign/catalogos/file.pdf?token=secret'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      return SupabaseCatalogRepository(
        client: client,
        httpClient: downloadClient,
      );
    }

    test('conserva el mensaje contextual si falla la URL firmada', () async {
      client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        accessToken: () async => 'expired-session',
        httpClient: MockClient((request) async => http.Response(
              jsonEncode({
                'statusCode': '403',
                'error': 'Unauthorized',
                'message': 'JWT expired',
              }),
              403,
              headers: {'content-type': 'application/json'},
              request: request,
            )),
      );
      final repository = SupabaseCatalogRepository(client: client);

      await expectLater(
        repository.download('org/id/v1/catalogo.pdf', requirePdf: true),
        throwsA(
          isA<CatalogFileException>()
              .having(
                  (error) => error.stage, 'etapa', CatalogFileStage.signedUrl)
              .having((error) => error.toString(), 'mensaje',
                  contains('JWT expired')),
        ),
      );
    });

    test('rechaza un PDF vacío aunque Storage responda HTTP 200', () async {
      final repository = repositoryFor(MockClient((request) async =>
          http.Response.bytes(const [], 200,
              headers: {'content-type': 'application/pdf'}, request: request)));

      await expectLater(
        repository.download('org/id/v1/catalogo.pdf', requirePdf: true),
        throwsA(
          isA<CatalogFileException>()
              .having(
                  (error) => error.stage, 'etapa', CatalogFileStage.validation)
              .having((error) => error.httpStatus, 'HTTP', 200)
              .having(
                  (error) => error.userMessage, 'mensaje', contains('vacío')),
        ),
      );
    });

    test('devuelve una sola vez el PDF válido de la URL firmada', () async {
      var requests = 0;
      final expected = Uint8List.fromList('%PDF-1.7\ncontenido'.codeUnits);
      final repository = repositoryFor(MockClient((request) async {
        requests++;
        return http.Response.bytes(expected, 200,
            headers: {'content-type': 'application/pdf'}, request: request);
      }));

      final result =
          await repository.download('org/id/v1/catalogo.pdf', requirePdf: true);

      expect(result, expected);
      expect(requests, 1);
    });

    test('conserva el código HTTP de una descarga rechazada', () async {
      final repository = repositoryFor(MockClient((request) async =>
          http.Response('{"message":"Object not found"}', 404,
              headers: {'content-type': 'application/json'},
              request: request)));

      await expectLater(
        repository.download('org/id/v1/catalogo.pdf', requirePdf: true),
        throwsA(
          isA<CatalogFileException>()
              .having((error) => error.stage, 'etapa',
                  CatalogFileStage.httpDownload)
              .having((error) => error.httpStatus, 'HTTP', 404)
              .having((error) => error.userMessage, 'mensaje real',
                  contains('Object not found')),
        ),
      );
    });

    test('rechaza HTTP 200 con HTML en vez de PDF', () async {
      final repository = repositoryFor(MockClient((request) async =>
          http.Response('<html>Error</html>', 200,
              headers: {'content-type': 'text/html'}, request: request)));

      await expectLater(
        repository.download('org/id/v1/catalogo.pdf', requirePdf: true),
        throwsA(
          isA<CatalogFileException>()
              .having(
                  (error) => error.stage, 'etapa', CatalogFileStage.validation)
              .having((error) => error.userMessage, 'mensaje',
                  contains('text/html')),
        ),
      );
    });

    test('rechaza application/pdf sin cabecera PDF', () async {
      final repository = repositoryFor(MockClient((request) async =>
          http.Response.bytes('contenido corrupto'.codeUnits, 200,
              headers: {'content-type': 'application/pdf'}, request: request)));

      await expectLater(
        repository.download('org/id/v1/catalogo.pdf', requirePdf: true),
        throwsA(
          isA<CatalogFileException>().having(
            (error) => error.userMessage,
            'mensaje',
            contains('%PDF-'),
          ),
        ),
      );
    });

    test('rechaza URL y nombre duplicado del bucket antes de firmar', () async {
      final repository = repositoryFor(MockClient(
          (_) async => throw StateError('no debe solicitar el archivo')));

      for (final path in [
        'https://example.test/catalogo.pdf',
        'catalogos/org/id/v1/catalogo.pdf',
      ]) {
        await expectLater(
          repository.download(path, requirePdf: true),
          throwsA(
            isA<CatalogFileException>().having(
              (error) => error.stage,
              'etapa',
              CatalogFileStage.metadata,
            ),
          ),
        );
      }
    });
  });

  test('el registro de errores oculta URLs, tokens y JWT', () {
    final sanitized = sanitizeCatalogError(
      'GET https://example.test/file?token=secret '
      'Authorization: Bearer private '
      'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature',
    );

    expect(sanitized, isNot(contains('secret')));
    expect(sanitized, isNot(contains('private')));
    expect(sanitized, isNot(contains('eyJhbGci')));
  });
}
