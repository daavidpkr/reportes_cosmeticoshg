import 'package:cosmeticos_hg_reportes/models/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

Catalog catalog({bool isNew = false, bool isUpdated = false}) => Catalog(
      id: 'catalog-id',
      organizationId: 'organization-id',
      title: 'Colección profesional',
      filePath: 'organization-id/catalog-id/v2/catalogo.pdf',
      coverPath: 'organization-id/catalog-id/v2/portada.webp',
      version: 2,
      pageCount: 24,
      status: CatalogStatus.publicado,
      active: true,
      featured: false,
      order: 1,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 10, 19),
      isNew: isNew,
      isUpdated: isUpdated,
    );

void main() {
  test('mapea las etiquetas calculadas por la vista sin recalcular fechas', () {
    final mapped = Catalog.fromJson({
      ...catalog().toCacheJson(),
      'es_nuevo': true,
      'es_actualizado': false,
    });

    expect(mapped.isNew, isTrue);
    expect(catalogMatchesFilter(mapped, CatalogFilter.newItems), isTrue);
    expect(catalogMatchesFilter(mapped, CatalogFilter.updated), isFalse);
  });

  test('los filtros Nuevo y Actualizado son mutuamente específicos', () {
    expect(catalogMatchesFilter(catalog(isNew: true), CatalogFilter.newItems),
        isTrue);
    expect(catalogMatchesFilter(catalog(isNew: true), CatalogFilter.updated),
        isFalse);
    expect(
        catalogMatchesFilter(catalog(isUpdated: true), CatalogFilter.updated),
        isTrue);
    expect(catalogMatchesFilter(catalog(), CatalogFilter.all), isTrue);
  });

  test('crea un nombre de descarga seguro y versionado', () {
    expect(safeCatalogFileName('Colección: Otoño / 2026', 3),
        'Colección_ Otoño _ 2026-v3.pdf');
    expect(safeCatalogFileName('   ', 1), 'catalogo-v1.pdf');
  });

  test('sólo habilita un PDF publicado con la ruta versionada esperada', () {
    expect(catalog().canOpen, isTrue);
    final pending = Catalog.fromJson({
      ...catalog().toCacheJson(),
      'estado': 'borrador',
      'archivo_path': null,
    });
    expect(pending.canOpen, isFalse);
    expect(pending.filePending, isTrue);
    expect(isValidPdfBytes('%PDF-1.7'.codeUnits), isTrue);
    expect(isValidPdfBytes(const []), isFalse);
  });
}
