import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../services/firebase_messaging_service.dart';

Future<AuthorizationStatus?> requestNotificationPermissionWithExplanation(
  BuildContext context,
) async {
  final service = FirebaseMessagingService.instance;
  if (!service.isSupported) return null;

  final current = await service.authorizationStatus();
  if (current == AuthorizationStatus.authorized ||
      current == AuthorizationStatus.provisional) {
    return current;
  }
  if (!context.mounted) return current;

  if (current == AuthorizationStatus.denied) {
    await _showDisabledDialog(context, service);
    return current;
  }

  final proceed =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Notificaciones de pagos'),
          content: const Text(
            'Activa las notificaciones para recibir avisos antes de los pagos programados.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ) ??
      false;
  if (!proceed) return current;

  final result = await service.requestPermission();
  if (result == AuthorizationStatus.denied && context.mounted) {
    await _showDisabledDialog(context, service);
  }
  return result;
}

Future<void> _showDisabledDialog(
  BuildContext context,
  FirebaseMessagingService service,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text('Notificaciones desactivadas'),
    content: const Text(
      'La aplicación seguirá funcionando. Puedes activar las notificaciones desde la configuración cuando quieras.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Cerrar'),
      ),
      FilledButton(
        onPressed: () {
          Navigator.pop(dialogContext);
          service.openNotificationSettings();
        },
        child: const Text('Abrir configuración'),
      ),
    ],
  ),
);
