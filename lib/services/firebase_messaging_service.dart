import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_open_request.dart';

typedef FcmTokenCallback = FutureOr<void> Function(String token);
typedef NotificationOpenCallback = FutureOr<void> Function(
    NotificationOpenRequest request);

class FirebaseMessagingService {
  FirebaseMessagingService._();

  static final FirebaseMessagingService instance = FirebaseMessagingService._();

  static const channel = AndroidNotificationChannel(
    'recordatorios_pago',
    'Recordatorios de pago',
    description: 'Avisos de fechas próximas de pago',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );
  static const _settingsChannel = MethodChannel(
    'com.example.reportes_cosmeticoshg/notification_settings',
  );

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final NotificationOpeningGuard _openingGuard = NotificationOpeningGuard();
  final StreamController<NotificationOpenRequest> _openings =
      StreamController<NotificationOpenRequest>.broadcast();

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenSubscription;
  FcmTokenCallback? _onTokenChanged;
  NotificationOpenCallback? _onOpen;
  final List<NotificationOpenRequest> _pendingOpenings = [];
  String? _token;
  bool _initialized = false;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get isInitialized => _initialized;
  String? get token => _token;
  Stream<NotificationOpenRequest> get openings => _openings.stream;

  Future<void> initialize({
    FcmTokenCallback? onTokenChanged,
    NotificationOpenCallback? onOpen,
  }) async {
    _onTokenChanged = onTokenChanged ?? _onTokenChanged;
    _onOpen = onOpen ?? _onOpen;
    if (_onOpen != null && _pendingOpenings.isNotEmpty) {
      final pending = List<NotificationOpenRequest>.of(_pendingOpenings);
      _pendingOpenings.clear();
      for (final request in pending) {
        await _deliverOpening(request);
      }
    }
    if (!isSupported || _initialized) return;
    _initialized = true;

    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _localNotifications.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handleLocalResponse,
      );
      final android = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(channel);

      _foregroundSubscription = FirebaseMessaging.onMessage.listen(
        _handleForegroundMessage,
      );
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleRemoteOpening,
      );
      _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
        _handleToken,
        onError: (Object error, StackTrace stackTrace) =>
            _debugError('renovación del token FCM', error, stackTrace),
      );

      await _loadToken();
      await _loadInitialOpenings();
      if (kDebugMode) {
        debugPrint('FCM Android inicializado; canal ${channel.id} creado.');
      }
    } catch (error, stackTrace) {
      _debugError('inicialización de notificaciones', error, stackTrace);
    }
  }

  Future<AuthorizationStatus> authorizationStatus() async {
    if (!isSupported) return AuthorizationStatus.notDetermined;
    return (await FirebaseMessaging.instance.getNotificationSettings())
        .authorizationStatus;
  }

  Future<AuthorizationStatus> requestPermission() async {
    if (!isSupported) return AuthorizationStatus.notDetermined;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );
      return settings.authorizationStatus;
    } catch (error, stackTrace) {
      _debugError('solicitud del permiso', error, stackTrace);
      return AuthorizationStatus.denied;
    }
  }

  Future<void> openNotificationSettings() async {
    if (!isSupported) return;
    try {
      await _settingsChannel.invokeMethod<void>('openNotificationSettings');
    } catch (error, stackTrace) {
      _debugError('apertura de configuración', error, stackTrace);
    }
  }

  Future<void> refreshToken() => _loadToken();

  Future<void> _loadToken() async {
    try {
      final value = await FirebaseMessaging.instance.getToken();
      if (value != null && value.isNotEmpty) await _handleToken(value);
    } catch (error, stackTrace) {
      _debugError('obtención del token FCM', error, stackTrace);
    }
  }

  Future<void> _handleToken(String value) async {
    _token = value;
    if (kDebugMode) {
      debugPrint('Token FCM disponible (${value.length} caracteres).');
    }
    try {
      await _onTokenChanged?.call(value);
    } catch (error, stackTrace) {
      _debugError('callback del token FCM', error, stackTrace);
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final title =
        message.notification?.title ?? message.data['title']?.toString();
    final body = message.notification?.body ?? message.data['body']?.toString();
    if ((title == null || title.trim().isEmpty) &&
        (body == null || body.trim().isEmpty)) {
      return;
    }
    try {
      await _localNotifications.show(
        id: message.messageId?.hashCode ??
            DateTime.now().millisecondsSinceEpoch,
        title: title?.trim().isEmpty ?? true ? 'Recordatorio de pago' : title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'recordatorios_pago',
            'Recordatorios de pago',
            channelDescription: 'Avisos de fechas próximas de pago',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    } catch (error, stackTrace) {
      _debugError('notificación en primer plano', error, stackTrace);
    }
  }

  Future<void> _loadInitialOpenings() async {
    final remote = await FirebaseMessaging.instance.getInitialMessage();
    if (remote != null) await _handleRemoteOpening(remote);

    final local = await _localNotifications.getNotificationAppLaunchDetails();
    if (local?.didNotificationLaunchApp ?? false) {
      await _processOpening(
        NotificationOpenRequest.fromPayload(
          local?.notificationResponse?.payload,
        ),
        'local:${local?.notificationResponse?.id}:${local?.notificationResponse?.payload}',
      );
    }
  }

  Future<void> _handleRemoteOpening(RemoteMessage message) => _processOpening(
        NotificationOpenRequest.fromData(message.data),
        message.messageId ?? 'remote:${jsonEncode(message.data)}',
      );

  void _handleLocalResponse(NotificationResponse response) {
    unawaited(
      _processOpening(
        NotificationOpenRequest.fromPayload(response.payload),
        'local:${response.id}:${response.payload}',
      ),
    );
  }

  Future<void> _processOpening(
    NotificationOpenRequest? request,
    String deduplicationKey,
  ) async {
    if (request == null || !_openingGuard.markIfNew(deduplicationKey)) return;
    _openings.add(request);
    if (_onOpen == null) {
      _pendingOpenings.add(request);
      return;
    }
    await _deliverOpening(request);
  }

  Future<void> _deliverOpening(NotificationOpenRequest request) async {
    try {
      await _onOpen?.call(request);
    } catch (error, stackTrace) {
      _debugError('apertura de notificación', error, stackTrace);
    }
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
    _foregroundSubscription = null;
    _openedSubscription = null;
    _tokenSubscription = null;
    _initialized = false;
  }

  void _debugError(String operation, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('Error durante $operation: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
