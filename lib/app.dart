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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        useMaterial3: true,
      ),
      home: _sesionIniciada
          ? ReporteScreen(onCerrarSesion: _cerrarSesion)
          : const LoginScreen(),
    );
  }
}
