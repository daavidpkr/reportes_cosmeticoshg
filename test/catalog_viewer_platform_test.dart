import 'package:cosmeticos_hg_reportes/screens/catalogs/catalog_viewer_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
