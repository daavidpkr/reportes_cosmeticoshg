import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void descargarArchivoWeb(Uint8List bytes, String nombre) {
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final enlace = web.HTMLAnchorElement()
    ..href = url
    ..download = nombre
    ..style.display = 'none';
  web.document.body?.append(enlace);
  enlace.click();
  enlace.remove();
  web.URL.revokeObjectURL(url);
}
