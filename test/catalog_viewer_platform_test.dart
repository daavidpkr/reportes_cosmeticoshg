import 'package:cosmeticos_hg_reportes/models/catalog.dart';
import 'package:cosmeticos_hg_reportes/screens/catalogs/catalog_viewer_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Catalog _catalog() => Catalog(
      id: 'catalog-id',
      organizationId: 'organization-id',
      title: 'Colección profesional',
      filePath: 'organization-id/catalog-id/v1/catalogo.pdf',
      version: 1,
      status: CatalogStatus.publicado,
      active: true,
      order: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 10, 21),
    );

Future<void> _pumpViewer(WidgetTester tester, Brightness brightness) =>
    tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: brightness,
          colorSchemeSeed: Colors.pink,
        ),
        home: CatalogViewerScreen(
          catalog: _catalog(),
          bytes: Uint8List(0),
        ),
      ),
    );

void main() {
  test('Windows usa PdfView y no PdfViewPinch', () {
    expect(
      usesPinchCatalogViewer(TargetPlatform.windows, isWeb: false),
      isFalse,
    );
  });

  test('Android y web conservan PdfViewPinch', () {
    expect(
      usesPinchCatalogViewer(TargetPlatform.android, isWeb: false),
      isTrue,
    );
    expect(
      usesPinchCatalogViewer(TargetPlatform.windows, isWeb: true),
      isTrue,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'pantalla completa oculta controles y conserva el visor en ${brightness.name}',
      (tester) async {
        await _pumpViewer(tester, brightness);
        final surface = tester.element(find.byKey(
          const Key('viewer-pdf-surface'),
        ));

        await tester.tap(find.byTooltip('Pantalla completa'));
        await tester.pumpAndSettle();

        expect(find.text('Colección profesional'), findsNothing);
        expect(find.byTooltip('Descargar'), findsNothing);
        expect(find.byTooltip('Salir de pantalla completa'), findsOneWidget);
        expect(
          find.byKey(const Key('viewer-fullscreen-page')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('viewer-fullscreen-zoom-in')),
          findsOneWidget,
        );
        expect(
          tester.element(find.byKey(const Key('viewer-pdf-surface'))),
          same(surface),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.byTooltip('Pantalla completa'), findsOneWidget);
        expect(find.byTooltip('Salir de pantalla completa'), findsNothing);
        expect(
          tester.element(find.byKey(const Key('viewer-pdf-surface'))),
          same(surface),
        );
      },
    );
  }

  testWidgets('Atrás sale de pantalla completa sin cerrar el visor',
      (tester) async {
    await _pumpViewer(tester, Brightness.light);
    await tester.tap(find.byTooltip('Pantalla completa'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(CatalogViewerScreen), findsOneWidget);
    expect(find.byTooltip('Pantalla completa'), findsOneWidget);
  });

  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    testWidgets('controles flotantes responden en ${size.width}x${size.height}',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpViewer(tester, Brightness.dark);

      await tester.tap(find.byTooltip('Pantalla completa'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('viewer-fullscreen-page')), findsOneWidget);
      expect(find.byTooltip('Salir de pantalla completa'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
