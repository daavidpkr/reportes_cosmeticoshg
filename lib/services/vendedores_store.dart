import 'package:shared_preferences/shared_preferences.dart';

class VendedoresStore {
  static const _clave = 'vendedores';
  final List<String> vendedores = [];

  Future<void> cargar() async {
    final preferencias = await SharedPreferences.getInstance();
    vendedores
      ..clear()
      ..addAll(preferencias.getStringList(_clave) ?? const []);
    vendedores.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<bool> agregar(String nombre) async {
    final limpio = nombre.trim();
    if (limpio.isEmpty ||
        vendedores.any((item) => item.toLowerCase() == limpio.toLowerCase())) {
      return false;
    }
    vendedores.add(limpio);
    vendedores.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    await _guardar();
    return true;
  }

  Future<void> eliminar(String nombre) async {
    vendedores.remove(nombre);
    await _guardar();
  }

  Future<void> _guardar() async {
    final preferencias = await SharedPreferences.getInstance();
    await preferencias.setStringList(_clave, vendedores);
  }
}
