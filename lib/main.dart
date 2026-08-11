import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/firebase_messaging_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
        await FirebaseMessagingService.instance.initialize();
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('Firebase Messaging no pudo inicializarse: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    }

    await dotenv.load(fileName: 'env');
    final url = dotenv.env['SUPABASE_URL']?.trim() ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';

    if (!_esUrlSupabaseValida(url) || anonKey.isEmpty) {
      throw const FormatException(
        'Completa SUPABASE_URL y SUPABASE_ANON_KEY en el archivo env.',
      );
    }

    await Supabase.initialize(url: url, publishableKey: anonKey);
    runApp(const CosmeticosHGApp());
  } catch (error) {
    runApp(_ErrorConfiguracionApp(mensaje: error.toString()));
  }
}

bool _esUrlSupabaseValida(String valor) {
  final uri = Uri.tryParse(valor);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.endsWith('.supabase.co');
}

/// Cliente compartido para los servicios y pantallas de la aplicación.
SupabaseClient get supabase => Supabase.instance.client;

class _ErrorConfiguracionApp extends StatelessWidget {
  const _ErrorConfiguracionApp({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 52, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'No se pudo configurar Supabase',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(mensaje, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      );
}
