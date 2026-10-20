import 'dart:typed_data';

import 'package:open_app_file/open_app_file.dart';

Future<void> openCatalogExternally(Uint8List bytes, String? localPath) async {
  if (localPath == null) {
    throw StateError(
        'Descarga el catálogo antes de abrirlo con otra aplicación.');
  }
  final result = await OpenAppFile.open(localPath, mimeType: 'application/pdf');
  if (result.type != ResultType.done) throw StateError(result.message);
}
