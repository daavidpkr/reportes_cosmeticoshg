import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef AutenticarUsuario = Future<void> Function(
  String correo,
  String contrasena,
);

class LoginScreen extends StatefulWidget {
  const LoginScreen({this.autenticar, super.key});

  /// Permite sustituir Supabase Auth durante las pruebas automatizadas.
  final AutenticarUsuario? autenticar;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _correoController = TextEditingController();
  final _contrasenaController = TextEditingController();
  bool _ocultarContrasena = true;
  bool _iniciandoSesion = false;
  String? _errorAcceso;

  @override
  void dispose() {
    _correoController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    FocusScope.of(context).unfocus();
    setState(() => _errorAcceso = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _iniciandoSesion = true);
    try {
      final correo = _correoController.text.trim();
      final contrasena = _contrasenaController.text;
      if (widget.autenticar != null) {
        await widget.autenticar!(correo, contrasena);
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: correo,
          password: contrasena,
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _errorAcceso = _mensajeAuth(error));
    } catch (_) {
      if (mounted) {
        setState(() => _errorAcceso =
            'No se pudo conectar. Revisa tu conexión e inténtalo nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _iniciandoSesion = false);
    }
  }

  String _mensajeAuth(AuthException error) {
    if (error.statusCode == '400' || error.statusCode == '401') {
      return 'Correo o contraseña incorrectos.';
    }
    return error.message;
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colores.surfaceContainerLowest,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: colores.primaryContainer,
                        child: Icon(
                          Icons.lock_outline,
                          size: 38,
                          color: colores.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'COSMÉTICOS HG',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Inicia sesión para acceder a los reportes',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colores.onSurfaceVariant),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        key: const Key('campoUsuario'),
                        controller: _correoController,
                        autofocus: true,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (valor) {
                          if (valor == null || valor.trim().isEmpty) {
                            return 'Ingresa tu correo electrónico.';
                          }
                          if (!valor.contains('@')) {
                            return 'Ingresa un correo válido.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('campoContrasena'),
                        controller: _contrasenaController,
                        obscureText: _ocultarContrasena,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _iniciarSesion(),
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.key_outlined),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _ocultarContrasena
                                ? 'Mostrar contraseña'
                                : 'Ocultar contraseña',
                            onPressed: () => setState(
                                () => _ocultarContrasena = !_ocultarContrasena),
                            icon: Icon(_ocultarContrasena
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                          ),
                        ),
                        validator: (valor) => valor == null || valor.isEmpty
                            ? 'Ingresa tu contraseña.'
                            : null,
                      ),
                      if (_errorAcceso != null) ...[
                        const SizedBox(height: 14),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _errorAcceso!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colores.error),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          key: const Key('botonIniciarSesion'),
                          onPressed: _iniciandoSesion ? null : _iniciarSesion,
                          icon: _iniciandoSesion
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: Text(_iniciandoSesion
                              ? 'Iniciando…'
                              : 'Iniciar sesión'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
