import 'package:cosmeticos_hg_reportes/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('bloquea el reporte hasta iniciar sesión', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const CosmeticosHGApp());
    await tester.pumpAndSettle();

    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.textContaining('REPORTE DE VENTAS'), findsNothing);

    await tester.enterText(find.byKey(const Key('campoUsuario')), 'otro');
    await tester.enterText(find.byKey(const Key('campoContrasena')), 'mala');
    await tester.tap(find.byKey(const Key('botonIniciarSesion')));
    await tester.pump();
    expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('campoUsuario')), 'admin');
    await tester.enterText(find.byKey(const Key('campoContrasena')), 'HG2026');
    await tester.tap(find.byKey(const Key('botonIniciarSesion')));
    await tester.pump();
    expect(find.textContaining('REPORTE DE VENTAS'), findsOneWidget);
  });

  testWidgets('restaura una sesión recordada que sigue vigente',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'mantener_sesion': true,
      'ultimo_acceso_sesion':
          DateTime.now().subtract(const Duration(days: 14)).toIso8601String(),
    });
    await tester.pumpWidget(const CosmeticosHGApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('REPORTE DE VENTAS'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsNothing);
  });

  testWidgets('cierra una sesión sin actividad durante más de 15 días',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'mantener_sesion': true,
      'ultimo_acceso_sesion':
          DateTime.now().subtract(const Duration(days: 16)).toIso8601String(),
    });
    await tester.pumpWidget(const CosmeticosHGApp());
    await tester.pumpAndSettle();

    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.textContaining('REPORTE DE VENTAS'), findsNothing);
  });
}
