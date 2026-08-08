import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'screens/reporte_screen.dart';

class CosmeticosHGApp extends StatefulWidget {
  const CosmeticosHGApp({super.key});

  @override
  State<CosmeticosHGApp> createState() => _CosmeticosHGAppState();
}

class _CosmeticosHGAppState extends State<CosmeticosHGApp> {
  static const _burgundy = Color(0xFF7A1F3D);
  static const _burgundyDark = Color(0xFF591530);
  static const _plum = Color(0xFF3D1A4A);
  static const _lilacSoft = Color(0xFFF2E9F4);
  static const _background = Color(0xFFF5F3F6);
  static const _ink = Color(0xFF241420);
  static const _inkSoft = Color(0xFF8A7C89);
  static const _line = Color(0xFFEAE3EA);

  final _auth = Supabase.instance.client.auth;
  late final StreamSubscription<AuthState> _authSubscription;
  late bool _sesionIniciada;
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    // Supabase restaura automáticamente la sesión guardada al inicializarse.
    _sesionIniciada = _auth.currentSession != null;
    _authSubscription = _auth.onAuthStateChange.listen((estado) {
      if (mounted) {
        setState(() => _sesionIniciada = estado.session != null);
      }
    });
    _cargarTema();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _cerrarSesion() => _auth.signOut();

  Future<void> _cargarTema() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted && (prefs.getBool('modo_oscuro') ?? false)) {
      setState(() => _themeMode = ThemeMode.dark);
    }
  }

  Future<void> _cambiarTema() async {
    final oscuro = _themeMode != ThemeMode.dark;
    setState(() => _themeMode = oscuro ? ThemeMode.dark : ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('modo_oscuro', oscuro);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cosméticos HG - Reportes',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: _burgundy,
          onPrimary: Colors.white,
          primaryContainer: _lilacSoft,
          onPrimaryContainer: _plum,
          secondary: _plum,
          onSecondary: Colors.white,
          secondaryContainer: _lilacSoft,
          onSecondaryContainer: _plum,
          surface: Colors.white,
          onSurface: _ink,
          error: Color(0xFFA8425A),
          outline: _line,
          outlineVariant: _line,
        ),
        scaffoldBackgroundColor: _background,
        canvasColor: Colors.white,
        dividerColor: _line,
        appBarTheme: const AppBarTheme(
          backgroundColor: _burgundyDark,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: _burgundyDark,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.white,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: TextStyle(color: _inkSoft),
          labelStyle: TextStyle(color: _inkSoft),
          floatingLabelStyle: TextStyle(color: _burgundy),
          iconColor: _plum,
          prefixIconColor: _plum,
          suffixIconColor: _inkSoft,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Color(0xFFC9A8D4), width: 1.5),
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            side: BorderSide(color: _line),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          labelTextStyle: WidgetStateProperty.resolveWith((estados) =>
              TextStyle(
                  color: estados.contains(WidgetState.selected)
                      ? _burgundy
                      : _inkSoft,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600)),
          iconTheme: WidgetStateProperty.resolveWith(
            (estados) => IconThemeData(
              color:
                  estados.contains(WidgetState.selected) ? _burgundy : _inkSoft,
              size: 20,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _burgundy,
            foregroundColor: Colors.white,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: _burgundy),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _plum,
            side: const BorderSide(color: _line),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: _burgundy,
          foregroundColor: Colors.white,
        ),
        progressIndicatorTheme:
            const ProgressIndicatorThemeData(color: _burgundy),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: _plum,
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD8A8B9),
          onPrimary: Color(0xFF3B0D20),
          secondary: Color(0xFFD3B3DE),
          surface: Color(0xFF201A1F),
          onSurface: Color(0xFFF3EAF0),
          outline: Color(0xFF63565F),
          error: Color(0xFFFFB4AB),
        ),
        scaffoldBackgroundColor: const Color(0xFF171216),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF3D1026),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(color: Color(0xFF241E23)),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF2B242A),
          border: OutlineInputBorder(),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF211A20),
          indicatorColor: Color(0xFF553043),
        ),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF241E23)),
        useMaterial3: true,
      ),
      home: _sesionIniciada
          ? ReporteScreen(
              onCerrarSesion: _cerrarSesion,
              onCambiarTema: _cambiarTema,
              modoOscuro: _themeMode == ThemeMode.dark,
            )
          : const LoginScreen(),
    );
  }
}
