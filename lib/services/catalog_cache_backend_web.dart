import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class CatalogCacheBackend {
  static const _name = 'catalogos-v1';
  String _url(String key) =>
      '${web.window.location.origin}/__catalog_cache__/$key';

  Future<web.Cache> _cache() => web.window.caches.open(_name).toDart;

  Future<Uint8List?> read(String key) async {
    final response = await (await _cache()).match(_url(key).toJS).toDart;
    if (response == null) return null;
    final buffer = await response.arrayBuffer().toDart;
    return Uint8List.fromList(buffer.toDart.asUint8List());
  }

  Future<String?> localPath(String key) async => null;

  Future<void> write(String key, Uint8List bytes) async {
    final headers = web.Headers()
      ..set('content-type', 'application/octet-stream');
    final response = web.Response(
      Uint8List.fromList(bytes).toJS,
      web.ResponseInit(headers: headers),
    );
    await (await _cache()).put(_url(key).toJS, response).toDart;
  }

  Future<void> delete(String key) async {
    await (await _cache()).delete(_url(key).toJS).toDart;
  }
}
