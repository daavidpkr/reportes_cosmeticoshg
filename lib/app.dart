import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'screens/reporte_screen.dart';

class CosmeticosHGApp extends StatefulWidget {
  const CosmeticosHGApp({super.key});

  @override
  State<CosmeticosHGApp> createState() => _CosmeticosHGAppState();
}

class _CosmeticosHGAppState extends State<CosmeticosHGApp> {
  final _auth = Supabase.instance.client.auth;
  late final StreamSubscription<AuthState> _authSubscription;
  late bool _sesionIniciada;

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
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _cerrarSesion() => _auth.signOut();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cosméticos HG - Reportes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7A1F3D),
          primary: const Color(0xFF7A1F3D),
          secondary: const Color(0xFF3D1A4A),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F3F6),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFEAE3EA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFC9A8D4), width: 1.5),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFEAE3EA)),
          ),
        ),
        useMaterial3: true,
      ),
      home: _sesionIniciada
          ? ReporteScreen(onCerrarSesion: _cerrarSesion)
          : const LoginScreen(),
    );
  }
}
