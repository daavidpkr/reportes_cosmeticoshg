import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
    final url = dotenv.env['SUPABASE_URL']?.trim() ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';

    if (!_esUrlSupabaseValida(url) || anonKey.isEmpty) {
      throw const FormatException(
        'Completa SUPABASE_URL y SUPABASE_ANON_KEY en el archivo .env.',
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
