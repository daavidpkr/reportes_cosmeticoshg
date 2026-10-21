import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class CatalogFullscreenController {
  CatalogFullscreenController({required this.onChanged}) {
    _fullscreenListener = ((web.Event _) {
      onChanged(web.document.fullscreenElement != null);
    }).toJS;
    web.document.addEventListener('fullscreenchange', _fullscreenListener);
  }

  final ValueChanged<bool> onChanged;
  late final web.EventListener _fullscreenListener;

  Future<void> enter() async {
    if (web.document.fullscreenElement != null) return;
    final root = web.document.documentElement;
    if (root == null) {
      throw StateError('El navegador no expuso el elemento raíz.');
    }
    await root.requestFullscreen().toDart;
  }

  Future<void> exit() async {
    if (web.document.fullscreenElement == null) return;
    await web.document.exitFullscreen().toDart;
  }

  void dispose() {
    web.document.removeEventListener('fullscreenchange', _fullscreenListener);
    if (web.document.fullscreenElement != null) {
      web.document.exitFullscreen();
    }
  }
}
