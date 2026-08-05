import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pantalla de prueba para la tabla `mensajes` de Supabase.
class SupabaseExampleScreen extends StatefulWidget {
  const SupabaseExampleScreen({super.key});

  @override
  State<SupabaseExampleScreen> createState() =>
      _SupabaseExampleScreenState();
}

class _SupabaseExampleScreenState extends State<SupabaseExampleScreen> {
  final _textController = TextEditingController();
  final _supabase = Supabase.instance.client;
  bool _enviando = false;

  Future<void> _enviarDato() async {
    final texto = _textController.text.trim();
    if (texto.isEmpty || _enviando) return;

    setState(() => _enviando = true);
    try {
      await _supabase.from('mensajes').insert({'contenido': texto});
      _textController.clear();
    } on PostgrestException catch (error) {
      _mostrarError('Supabase rechazó el dato: ${error.message}');
    } catch (error) {
      _mostrarError('No se pudo enviar el mensaje: $error');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Prueba Supabase en tiempo real')),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _supabase
                    .from('mensajes')
                    .stream(primaryKey: ['id'])
                    .order('created_at'),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Error al leer datos: ${snapshot.error}'),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final mensajes = snapshot.data!;
                  if (mensajes.isEmpty) {
                    return const Center(child: Text('Todavía no hay mensajes.'));
                  }
                  return ListView.builder(
                    itemCount: mensajes.length,
                    itemBuilder: (context, index) => ListTile(
                      title: Text(mensajes[index]['contenido']?.toString() ?? ''),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        decoration:
                            const InputDecoration(hintText: 'Escribe algo...'),
                        onSubmitted: (_) => _enviarDato(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Enviar',
                      onPressed: _enviando ? null : _enviarDato,
                      icon: _enviando
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}
