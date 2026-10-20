import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> openCatalogExternally(Uint8List bytes, String? localPath) async {
  final blob =
      web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/pdf'));
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
  Future<void>.delayed(
      const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
