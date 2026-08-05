import 'package:cosmeticos_hg_reportes/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('valida el formulario antes de autenticar', (tester) async {
    var llamadas = 0;
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(autenticar: (_, __) async => llamadas++),
    ));

    await tester.tap(find.byKey(const Key('botonIniciarSesion')));
    await tester.pump();

    expect(find.text('Ingresa tu correo electrónico.'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
    expect(llamadas, 0);
  });

  testWidgets('envía correo y contraseña al proveedor de autenticación',
      (tester) async {
    String? correoRecibido;
    String? contrasenaRecibida;
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(
        autenticar: (correo, contrasena) async {
          correoRecibido = correo;
          contrasenaRecibida = contrasena;
        },
      ),
    ));

    await tester.enterText(
      find.byKey(const Key('campoUsuario')),
      ' usuario@ejemplo.com ',
    );
    await tester.enterText(
      find.byKey(const Key('campoContrasena')),
      'clave-segura',
    );
    await tester.tap(find.byKey(const Key('botonIniciarSesion')));
    await tester.pumpAndSettle();

    expect(correoRecibido, 'usuario@ejemplo.com');
    expect(contrasenaRecibida, 'clave-segura');
  });
}
