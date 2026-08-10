import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'screens/reporte_screen.dart';
import 'theme/hg_theme.dart';

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
          labelTextStyle: WidgetStateProperty.resolveWith(
            (estados) => TextStyle(
              color: estados.contains(WidgetState.selected)
                  ? _burgundy
                  : _inkSoft,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (estados) => IconThemeData(
              color: estados.contains(WidgetState.selected)
                  ? _burgundy
                  : _inkSoft,
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
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: _burgundy,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: _plum,
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        extensions: const [HgThemeColors.light],
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFA84D70),
          onPrimary: Colors.white,
          primaryContainer: Color(0xFF482232),
          onPrimaryContainer: Color(0xFFF5EFF4),
          secondary: Color(0xFFC9A8D4),
          onSecondary: Color(0xFF2B162F),
          secondaryContainer: Color(0xFF3A293E),
          onSecondaryContainer: Color(0xFFF5EFF4),
          surface: Color(0xFF251C26),
          onSurface: Color(0xFFF5EFF4),
          surfaceContainerHighest: Color(0xFF2D232E),
          onSurfaceVariant: Color(0xFFBBAFBA),
          outline: Color(0xFF493A49),
          outlineVariant: Color(0xFF493A49),
          error: Color(0xFFE17A91),
          onError: Color(0xFF2D0B14),
        ),
        scaffoldBackgroundColor: const Color(0xFF171217),
        canvasColor: const Color(0xFF1D161E),
        dividerColor: const Color(0xFF493A49),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF3B1027),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Color(0xFF3B1027),
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Color(0xFF1D161E),
            systemNavigationBarIconBrightness: Brightness.light,
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Color(0xFF251C26),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            side: BorderSide(color: Color(0xFF493A49)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF2D232E),
          hintStyle: TextStyle(color: Color(0xFF81747F)),
          labelStyle: TextStyle(color: Color(0xFFBBAFBA)),
          floatingLabelStyle: TextStyle(color: Color(0xFFC9A8D4)),
          iconColor: Color(0xFFC9A8D4),
          prefixIconColor: Color(0xFFC9A8D4),
          suffixIconColor: Color(0xFFBBAFBA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Color(0xFF493A49)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Color(0xFF493A49)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Color(0xFFA84D70), width: 1.5),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF1D161E),
          indicatorColor: const Color(0xFF482232),
          surfaceTintColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFFC9A8D4)
                  : const Color(0xFFBBAFBA),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFFC9A8D4)
                  : const Color(0xFFBBAFBA),
              size: 20,
            ),
          ),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF251C26),
          surfaceTintColor: Colors.transparent,
        ),
        dropdownMenuTheme: const DropdownMenuThemeData(
          menuStyle: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(Color(0xFF251C26)),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7A1F3D),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF493A49),
            disabledForegroundColor: const Color(0xFF81747F),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFC9A8D4)),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFC9A8D4),
            side: const BorderSide(color: Color(0xFF493A49)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF7A1F3D),
          foregroundColor: Colors.white,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFFA84D70),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF3D1A4A),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        dataTableTheme: DataTableThemeData(
          headingRowColor: const WidgetStatePropertyAll(Color(0xFF211922)),
          headingTextStyle: const TextStyle(
            color: Color(0xFFBBAFBA),
            fontWeight: FontWeight.w600,
          ),
          dataTextStyle: const TextStyle(color: Color(0xFFF5EFF4)),
          dividerThickness: .7,
          dataRowColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected) ||
                states.contains(WidgetState.hovered)) {
              return const Color(0x2EA84D70);
            }
            return Colors.transparent;
          }),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFBBAFBA)),
        extensions: const [HgThemeColors.dark],
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
