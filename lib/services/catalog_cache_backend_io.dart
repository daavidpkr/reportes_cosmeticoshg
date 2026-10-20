import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class CatalogCacheBackend {
  Future<Directory> _root() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}catalogos');
  }

  Future<String> _path(String key) async =>
      '${(await _root()).path}${Platform.pathSeparator}${key.replaceAll('/', Platform.pathSeparator)}';

  Future<Uint8List?> read(String key) async {
    final file = File(await _path(key));
    return file.existsSync() ? file.readAsBytes() : null;
  }

  Future<String?> localPath(String key) async {
    final path = await _path(key);
    return File(path).existsSync() ? path : null;
  }

  Future<void> write(String key, Uint8List bytes) async {
    final path = await _path(key);
    final target = File(path);
    await target.parent.create(recursive: true);
    final partial = File('$path.part');
    await partial.writeAsBytes(bytes, flush: true);
    if (await target.exists()) await target.delete();
    await partial.rename(path);
  }

  Future<void> delete(String key) async {
    final file = File(await _path(key));
    if (await file.exists()) await file.delete();
  }
}
