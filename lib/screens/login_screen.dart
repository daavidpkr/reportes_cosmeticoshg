import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onInicioExitoso, super.key});

  final ValueChanged<bool> onInicioExitoso;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _usuarioValido = 'admin';
  static const _contrasenaValida = 'HG2026';
  final _formKey = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _contrasenaController = TextEditingController();
  bool _ocultarContrasena = true;
  bool _mantenerSesion = false;
  String? _errorAcceso;

  @override
  void dispose() {
    _usuarioController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }

  void _iniciarSesion() {
    FocusScope.of(context).unfocus();
    setState(() => _errorAcceso = null);
    if (!_formKey.currentState!.validate()) return;
    if (_usuarioController.text.trim() == _usuarioValido &&
        _contrasenaController.text == _contrasenaValida) {
      widget.onInicioExitoso(_mantenerSesion);
      return;
    }
    setState(() => _errorAcceso = 'Usuario o contraseña incorrectos.');
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
                        child: Icon(Icons.lock_outline,
                            size: 38, color: colores.onPrimaryContainer),
                      ),
                      const SizedBox(height: 20),
                      Text('COSMÉTICOS HG',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text('Inicia sesión para acceder a los reportes',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colores.onSurfaceVariant)),
                      const SizedBox(height: 28),
                      TextFormField(
                        key: const Key('campoUsuario'),
                        controller: _usuarioController,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Usuario',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (valor) =>
                            valor == null || valor.trim().isEmpty
                                ? 'Ingresa tu usuario.'
                                : null,
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
                      CheckboxListTile(
                        key: const Key('mantenerSesion'),
                        value: _mantenerSesion,
                        onChanged: (valor) =>
                            setState(() => _mantenerSesion = valor ?? false),
                        title: const Text('Mantener la sesión iniciada'),
                        subtitle: const Text(
                          'Se cerrará después de 15 días sin entrar.',
                        ),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (_errorAcceso != null) ...[
                        const SizedBox(height: 14),
                        Semantics(
                          liveRegion: true,
                          child: Text(_errorAcceso!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colores.error)),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          key: const Key('botonIniciarSesion'),
                          onPressed: _iniciarSesion,
                          icon: const Icon(Icons.login),
                          label: const Text('Iniciar sesión'),
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
