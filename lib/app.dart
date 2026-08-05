import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/login_screen.dart';
import 'screens/reporte_screen.dart';

class CosmeticosHGApp extends StatefulWidget {
  const CosmeticosHGApp({super.key});

  @override
  State<CosmeticosHGApp> createState() => _CosmeticosHGAppState();
}

class _CosmeticosHGAppState extends State<CosmeticosHGApp> {
  static const _claveMantenerSesion = 'mantener_sesion';
  static const _claveUltimoAcceso = 'ultimo_acceso_sesion';
  static const _vigenciaSesion = Duration(days: 15);

  bool _inicializando = true;
  bool _sesionIniciada = false;

  @override
  void initState() {
    super.initState();
    _restaurarSesion();
  }

  Future<void> _restaurarSesion() async {
    final preferencias = await SharedPreferences.getInstance();
    final mantener = preferencias.getBool(_claveMantenerSesion) ?? false;
    final ultimoAccesoTexto = preferencias.getString(_claveUltimoAcceso);
    final ultimoAcceso =
        ultimoAccesoTexto == null ? null : DateTime.tryParse(ultimoAccesoTexto);
    final sesionVigente = mantener &&
        ultimoAcceso != null &&
        DateTime.now().difference(ultimoAcceso) <= _vigenciaSesion;

    if (sesionVigente) {
      await preferencias.setString(
        _claveUltimoAcceso,
        DateTime.now().toIso8601String(),
      );
    } else if (mantener) {
      await preferencias.remove(_claveMantenerSesion);
      await preferencias.remove(_claveUltimoAcceso);
    }

    if (!mounted) return;
    setState(() {
      _sesionIniciada = sesionVigente;
      _inicializando = false;
    });
  }

  Future<void> _iniciarSesion(bool mantenerSesion) async {
    final preferencias = await SharedPreferences.getInstance();
    if (mantenerSesion) {
      await preferencias.setBool(_claveMantenerSesion, true);
      await preferencias.setString(
        _claveUltimoAcceso,
        DateTime.now().toIso8601String(),
      );
    } else {
      await preferencias.remove(_claveMantenerSesion);
      await preferencias.remove(_claveUltimoAcceso);
    }
    if (mounted) setState(() => _sesionIniciada = true);
  }

  Future<void> _cerrarSesion() async {
    final preferencias = await SharedPreferences.getInstance();
    await preferencias.remove(_claveMantenerSesion);
    await preferencias.remove(_claveUltimoAcceso);
    if (mounted) setState(() => _sesionIniciada = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cosméticos HG - Reportes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        useMaterial3: true,
      ),
      home: _inicializando
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _sesionIniciada
              ? ReporteScreen(
                  onCerrarSesion: _cerrarSesion,
                )
              : LoginScreen(
                  onInicioExitoso: _iniciarSesion,
                ),
    );
  }
}
