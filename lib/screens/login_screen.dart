import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/hg_theme.dart';

typedef AutenticarUsuario = Future<void> Function(
    String correo, String contrasena);

class LoginScreen extends StatefulWidget {
  const LoginScreen({this.autenticar, super.key});

  /// Permite sustituir Supabase Auth durante las pruebas automatizadas.
  final AutenticarUsuario? autenticar;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _burgundy = Color(0xFF7A1F3D);
  static const _burgundyDark = Color(0xFF591530);
  static const _plum = Color(0xFF3D1A4A);
  static const _gold = Color(0xFFC9A24C);
  static const _goldSoft = Color(0xFFF1E4C0);

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
      TextInput.finishAutofillContext(shouldSave: true);
    } on AuthException catch (error) {
      if (mounted) setState(() => _errorAcceso = _mensajeAuth(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorAcceso =
              'No se pudo conectar. Revisa tu conexión e inténtalo nuevamente.',
        );
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
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: oscuro
                ? const [Color(0xFF171217), Color(0xFF1D161E)]
                : const [Color(0xFFF8F5F9), Color(0xFFEFE9F0)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned(
              left: -130,
              top: -120,
              child: _Glow(size: 410, color: Color(0x59C9A8D4)),
            ),
            const Positioned(
              right: -120,
              bottom: -150,
              child: _Glow(size: 430, color: Color(0x40C9A24C)),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: _buildCard(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.hg.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0x99000000)
                : const Color(0x243D1A4A),
            blurRadius: 60,
            spreadRadius: -20,
            offset: const Offset(0, 28),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: -72,
            child: Container(
              width: 260,
              height: 130,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.elliptical(130, 65),
                  bottomRight: Radius.elliptical(130, 65),
                ),
                gradient: LinearGradient(colors: [_burgundyDark, _plum]),
              ),
              foregroundDecoration: const BoxDecoration(
                color: Color(0xEFFFFFFF),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 36, 32, 36),
            child: AutofillGroup(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLockIcon(),
                    const SizedBox(height: 18),
                    Text(
                      'COSMÉTICOS HG',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.hg.plum,
                        fontSize: 21,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Inicia sesión para acceder a los reportes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.hg.mutedText,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 26),
                    _buildEmailField(),
                    const SizedBox(height: 14),
                    _buildPasswordField(),
                    if (_errorAcceso != null) ...[
                      const SizedBox(height: 14),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _errorAcceso!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFB3261E),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    _buildLoginButton(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockIcon() {
    return Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-.36, -.44),
          colors: [_goldSoft, _gold],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x66C9A24C),
            blurRadius: 18,
            spreadRadius: -4,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.lock_outline_rounded,
        color: _burgundyDark,
        size: 28,
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      key: const Key('campoUsuario'),
      controller: _correoController,
      autofocus: true,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.username, AutofillHints.email],
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 13.5,
      ),
      decoration: _fieldDecoration(
        hintText: 'Correo electrónico',
        prefixIcon: Icons.email_outlined,
      ),
      validator: (valor) {
        if (valor == null || valor.trim().isEmpty) {
          return 'Ingresa tu correo electrónico.';
        }
        if (!valor.contains('@')) return 'Ingresa un correo válido.';
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      key: const Key('campoContrasena'),
      controller: _contrasenaController,
      obscureText: _ocultarContrasena,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      onFieldSubmitted: (_) => _iniciarSesion(),
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 13.5,
      ),
      decoration: _fieldDecoration(
        hintText: 'Contraseña',
        prefixIcon: Icons.key_outlined,
        suffix: IconButton(
          tooltip:
              _ocultarContrasena ? 'Mostrar contraseña' : 'Ocultar contraseña',
          onPressed: () =>
              setState(() => _ocultarContrasena = !_ocultarContrasena),
          icon: Icon(
            _ocultarContrasena
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 19,
            color: context.hg.mutedText,
          ),
        ),
      ),
      validator: (valor) =>
          valor == null || valor.isEmpty ? 'Ingresa tu contraseña.' : null,
    );
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: context.hg.disabledText, fontSize: 13.5),
      prefixIcon: Icon(prefixIcon, color: context.hg.burgundy, size: 19),
      suffixIcon: suffix,
      filled: true,
      fillColor: context.hg.input,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: border(Theme.of(context).colorScheme.outlineVariant),
      enabledBorder: border(Theme.of(context).colorScheme.outlineVariant),
      focusedBorder: border(context.hg.burgundy, 1.5),
      errorBorder: border(const Color(0xFFB3261E)),
      focusedErrorBorder: border(const Color(0xFFB3261E), 1.5),
      errorStyle: const TextStyle(fontSize: 11.5),
    );
  }

  Widget _buildLoginButton() {
    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(colors: [_burgundy, _plum]),
        boxShadow: const [
          BoxShadow(
            color: Color(0x667A1F3D),
            blurRadius: 22,
            spreadRadius: -6,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          key: const Key('botonIniciarSesion'),
          onTap: _iniciandoSesion ? null : _iniciarSesion,
          borderRadius: BorderRadius.circular(999),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_iniciandoSesion)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(
                    Icons.login_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                const SizedBox(width: 9),
                Text(
                  _iniciandoSesion ? 'Iniciando…' : 'Iniciar sesión',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withAlpha(0)]),
        ),
      );
}
