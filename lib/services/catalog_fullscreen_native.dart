import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CatalogFullscreenController {
  CatalogFullscreenController({required this.onChanged});

  final ValueChanged<bool> onChanged;
  bool _active = false;

  Future<void> enter() async {
    if (_active) return;
    _active = true;
    onChanged(true);
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    } catch (_) {
      _active = false;
      onChanged(false);
      rethrow;
    }
  }

  Future<void> exit() async {
    if (!_active) return;
    _active = false;
    onChanged(false);
    if (defaultTargetPlatform == TargetPlatform.android) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void dispose() {
    if (_active && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
      );
    }
    _active = false;
  }
}
