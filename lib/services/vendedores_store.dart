import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'request_id.dart';

class Vendedor {
  const Vendedor({required this.codigo, required this.nombre});

  final String codigo;
  final String nombre;

  String get etiqueta => codigo.isEmpty ? nombre : '$codigo - $nombre';

  Map<String, String> toJson() => {'codigo': codigo, 'nombre': nombre};
}

class VendedoresStore {
  static const _clave = 'vendedores_con_codigo';

  // Indica que esta PC ya migró sus vendedores locales.
  static const _claveMigracion = 'vendedores_migrados_a_supabase_v1';

  final SupabaseClient _client = Supabase.instance.client;

  final List<Vendedor> vendedores = [];

  Future<void> cargar() async {
    final preferencias = await SharedPreferences.getInstance();

    final migracionRealizada = preferencias.getBool(_claveMigracion) ?? false;

    // Primera ejecución después de la migración:
    // recupera vendedores existentes de SharedPreferences
    // y los envía a Supabase.
    if (!migracionRealizada) {
      await _migrarVendedoresLocales(preferencias);

      await preferencias.setBool(_claveMigracion, true);
    }

    // Desde este punto Supabase es la fuente principal.
    await _cargarDesdeSupabase();
  }

  Future<void> _migrarVendedoresLocales(SharedPreferences preferencias) async {
    final locales = <Vendedor>[];

    final guardados = preferencias.getStringList(_clave);

    if (guardados != null) {
      for (final dato in guardados) {
        try {
          final mapa = jsonDecode(dato) as Map<String, dynamic>;

          final codigo =
              (mapa['codigo']?.toString() ?? '').trim().toUpperCase();

          final nombre = (mapa['nombre']?.toString() ?? '').trim();

          if (codigo.isEmpty || nombre.isEmpty) continue;

          locales.add(Vendedor(codigo: codigo, nombre: nombre));
        } catch (_) {
          // Ignora registros locales dañados.
        }
      }
    }

    // Compatibilidad con la versión antigua que solamente
    // almacenaba nombres. Estos registros no tienen código,
    // por lo que no se suben automáticamente.
    //
    // Permanecen intactos en SharedPreferences.
    if (locales.isEmpty) return;

    for (final vendedor in locales) {
      await _client.rpc('enterprise_save_seller', params: {
        'p_request_id': newRequestId(),
        'p_old_code': null,
        'p_code': vendedor.codigo,
        'p_name': vendedor.nombre,
      });
    }
  }

  Future<void> _cargarDesdeSupabase() async {
    final respuesta = await _client
        .from('vendedores')
        .select('codigo, nombre')
        .order('codigo', ascending: true);

    vendedores
      ..clear()
      ..addAll(
        List<Map<String, dynamic>>.from(respuesta).map(
          (dato) => Vendedor(
            codigo: dato['codigo']?.toString().trim().toUpperCase() ?? '',
            nombre: dato['nombre']?.toString().trim() ?? '',
          ),
        ),
      );

    _ordenar();
  }

  Future<bool> agregar(String codigo, String nombre) async {
    final codigoLimpio = codigo.trim().toUpperCase();
    final nombreLimpio = nombre.trim();

    if (codigoLimpio.isEmpty || nombreLimpio.isEmpty) {
      return false;
    }

    if (vendedores.any(
      (item) =>
          item.codigo.toLowerCase() == codigoLimpio.toLowerCase() ||
          item.nombre.toLowerCase() == nombreLimpio.toLowerCase(),
    )) {
      return false;
    }

    try {
      final saved = await _client.rpc('enterprise_save_seller', params: {
        'p_request_id': newRequestId(),
        'p_old_code': null,
        'p_code': codigoLimpio,
        'p_name': nombreLimpio,
      });
      if (saved != true) return false;

      vendedores.add(Vendedor(codigo: codigoLimpio, nombre: nombreLimpio));

      _ordenar();

      return true;
    } on PostgrestException {
      return false;
    }
  }

  Future<void> eliminar(Vendedor vendedor) async {
    await _client.rpc('enterprise_delete_seller', params: {
      'p_request_id': newRequestId(),
      'p_code': vendedor.codigo,
    });

    vendedores.remove(vendedor);
  }

  Future<bool> editar(Vendedor anterior, String codigo, String nombre) async {
    final codigoLimpio = codigo.trim().toUpperCase();
    final nombreLimpio = nombre.trim();
    if (codigoLimpio.isEmpty || nombreLimpio.isEmpty) return false;
    if (vendedores.any(
      (item) =>
          !identical(item, anterior) &&
          (item.codigo.toLowerCase() == codigoLimpio.toLowerCase() ||
              item.nombre.toLowerCase() == nombreLimpio.toLowerCase()),
    )) {
      return false;
    }
    try {
      final saved = await _client.rpc('enterprise_save_seller', params: {
        'p_request_id': newRequestId(),
        'p_old_code': anterior.codigo,
        'p_code': codigoLimpio,
        'p_name': nombreLimpio,
      });
      if (saved != true) return false;
      final indice = vendedores.indexOf(anterior);
      if (indice >= 0) {
        vendedores[indice] = Vendedor(
          codigo: codigoLimpio,
          nombre: nombreLimpio,
        );
      }
      _ordenar();
      return true;
    } on PostgrestException {
      return false;
    }
  }

  void _ordenar() {
    vendedores.sort(
      (a, b) => a.codigo.toLowerCase().compareTo(b.codigo.toLowerCase()),
    );
  }
}
