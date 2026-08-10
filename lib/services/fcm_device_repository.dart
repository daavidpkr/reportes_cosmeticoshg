import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class FcmDeviceDataSource {
  Future<void> register(String token);
  Future<void> deactivate(String token);
}

class FcmDeviceRepository implements FcmDeviceDataSource {
  FcmDeviceRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<void> register(String token) =>
      _client.rpc<void>('register_fcm_device',
          params: {'device_token': token, 'device_platform': 'android'});
  @override
  Future<void> deactivate(String token) => _client
      .rpc<void>('deactivate_fcm_device', params: {'device_token': token});
}

class FcmDeviceCoordinator {
  FcmDeviceCoordinator(
      {required FcmDeviceDataSource repository,
      Duration retryDelay = const Duration(seconds: 5)})
      : _repository = repository,
        _retryDelay = retryDelay;
  final FcmDeviceDataSource _repository;
  final Duration _retryDelay;
  String? _token;
  String? _registeredToken;
  bool _authenticated = false;
  Timer? _retry;

  Future<void> onTokenChanged(String token) async {
    _token = token;
    if (_authenticated) await _register();
  }

  Future<void> onSignedIn() async {
    _authenticated = true;
    await _register();
  }

  Future<void> onSignedOut() async {
    final current = _token;
    _authenticated = false;
    _retry?.cancel();
    if (current != null) {
      try {
        await _repository.deactivate(current);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('No se pudo desactivar el dispositivo: $error');
        }
      }
    }
    _registeredToken = null;
  }

  Future<void> _register() async {
    final current = _token;
    if (!_authenticated || current == null || current == _registeredToken) {
      return;
    }
    try {
      final previous = _registeredToken;
      await _repository.register(current);
      if (previous != null && previous != current) {
        await _repository.deactivate(previous);
      }
      _registeredToken = current;
      _retry?.cancel();
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
            'Registro FCM pendiente (${current.length} caracteres): $error');
      }
      _retry?.cancel();
      _retry = Timer(_retryDelay, () => unawaited(_register()));
    }
  }

  void dispose() => _retry?.cancel();
}
