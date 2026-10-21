import 'dart:async';
import 'dart:typed_data';

import 'package:cosmeticos_hg_reportes/models/catalog.dart';
import 'package:cosmeticos_hg_reportes/screens/catalogs/catalog_cover.dart';
import 'package:cosmeticos_hg_reportes/screens/catalogs/featured_catalog_banner.dart';
import 'package:cosmeticos_hg_reportes/theme/hg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Catalog _catalog({required int version, String? coverPath}) => Catalog(
      id: 'featured',
      organizationId: 'org',
      title: 'Destacado web estable',
      filePath: 'org/featured/v$version/catalogo.pdf',
      coverPath: coverPath,
      version: version,
      pageCount: 12,
      status: CatalogStatus.publicado,
      active: true,
      featured: true,
      order: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 10, 20),
    );

Widget _app(Catalog catalog, Future<Uint8List?> cover) => MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: const [HgThemeColors.light],
      ),
      home: Scaffold(
        body: FeaturedCatalogBanner(
          catalog: catalog,
          mobile: false,
          cover: CatalogCover(
            catalog: catalog,
            bytes: cover,
            featured: true,
          ),
          metadata: '20 oct 2026 · v${catalog.version} · 12 páginas',
          onView: () {},
          onDownload: () {},
        ),
      ),
    );

void main() {
  testWidgets('banner web permanece visible sin portada y tras fallo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final withoutCover = _catalog(version: 1);
    await tester.pumpWidget(_app(withoutCover, Future.value(null)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));

    expect(find.byKey(const ValueKey('featured-featured-v1')), findsOneWidget);
    expect(find.byKey(const Key('featured-cover-placeholder')), findsOneWidget);
    expect(find.text('Destacado web estable'), findsOneWidget);
    expect(find.text('Ver'), findsOneWidget);
    expect(find.byTooltip('Descargar'), findsOneWidget);

    final failedCover = Completer<Uint8List?>();
    final withCover = _catalog(
      version: 2,
      coverPath: 'org/featured/v2/portada.webp',
    );
    await tester.pumpWidget(_app(withCover, failedCover.future));
    await tester.pump(const Duration(seconds: 15));

    expect(find.byKey(const ValueKey('featured-featured-v2')), findsOneWidget);
    expect(find.byKey(const Key('featured-cover-placeholder')), findsOneWidget);
    expect(find.text('Destacado web estable'), findsOneWidget);

    failedCover.completeError(StateError('portada no disponible'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('featured-featured-v2')), findsOneWidget);
    expect(find.byKey(const Key('featured-cover-placeholder')), findsOneWidget);
    expect(find.text('Destacado web estable'), findsOneWidget);
    expect(find.text('Ver'), findsOneWidget);
    expect(find.byTooltip('Descargar'), findsOneWidget);
  });
}
