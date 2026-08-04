import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Vendedor {
  const Vendedor({required this.codigo, required this.nombre});

  final String codigo;
  final String nombre;

  String get etiqueta => codigo.isEmpty ? nombre : '$codigo - $nombre';

  Map<String, String> toJson() => {'codigo': codigo, 'nombre': nombre};
}

class VendedoresStore {
  static const _clave = 'vendedores_con_codigo';
  static const _claveAnterior = 'vendedores';
  final List<Vendedor> vendedores = [];

  Future<void> cargar() async {
    final preferencias = await SharedPreferences.getInstance();
    final guardados = preferencias.getStringList(_clave);
    vendedores.clear();
    if (guardados != null) {
      for (final dato in guardados) {
        final mapa = jsonDecode(dato) as Map<String, dynamic>;
        vendedores.add(Vendedor(
          codigo: mapa['codigo'] as String? ?? '',
          nombre: mapa['nombre'] as String? ?? '',
        ));
      }
    } else {
      vendedores.addAll(
        (preferencias.getStringList(_claveAnterior) ?? const [])
            .map((nombre) => Vendedor(codigo: '', nombre: nombre)),
      );
      await _guardar();
    }
    _ordenar();
  }

  Future<bool> agregar(String codigo, String nombre) async {
    final codigoLimpio = codigo.trim().toUpperCase();
    final nombreLimpio = nombre.trim();
    if (codigoLimpio.isEmpty || nombreLimpio.isEmpty) return false;
    if (vendedores.any((item) =>
        item.codigo.toLowerCase() == codigoLimpio.toLowerCase() ||
        item.nombre.toLowerCase() == nombreLimpio.toLowerCase())) {
      return false;
    }
    vendedores.add(Vendedor(codigo: codigoLimpio, nombre: nombreLimpio));
    _ordenar();
    await _guardar();
    return true;
  }

  Future<void> eliminar(Vendedor vendedor) async {
    vendedores.remove(vendedor);
    await _guardar();
  }

  void _ordenar() => vendedores.sort(
        (a, b) => a.codigo.toLowerCase().compareTo(b.codigo.toLowerCase()),
      );

  Future<void> _guardar() async {
    final preferencias = await SharedPreferences.getInstance();
    await preferencias.setStringList(
      _clave,
      vendedores.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }
}
