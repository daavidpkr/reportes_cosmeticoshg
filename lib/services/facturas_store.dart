import '../models/factura.dart';

enum ResultadoFactura { agregada, invalida, mesIncorrecto }

class FacturasStore {
  FacturasStore._();

  static final FacturasStore instance = FacturasStore._();
  final Map<String, Factura> _facturas = {};
  int? mesPermitido;
  int? anioPermitido;

  int get cantidad => _facturas.values.toSet().length;

  Factura? buscar(String referencia) => _facturas[referencia.trim()];

  void limpiar() => _facturas.clear();

  void eliminar(String referencia) {
    final factura = buscar(referencia);
    if (factura == null) return;
    _facturas.removeWhere((_, item) => identical(item, factura));
  }

  List<Factura> get facturas => _facturas.values.toSet().toList();

  void cargar(Iterable<Factura> facturas) {
    limpiar();
    for (final factura in facturas) {
      _registrar(factura);
    }
  }

  ResultadoFactura agregarDesdeTexto(String texto) {
    final resultado = analizarTexto(texto);
    if (resultado.resultado == ResultadoFactura.agregada) {
      _registrar(resultado.factura!);
    }
    return resultado.resultado;
  }

  ({ResultadoFactura resultado, Factura? factura}) analizarTexto(String texto) {
    final secuencial = referenciaDesdeTexto(texto);
    if (secuencial == null || secuencial.isEmpty) {
      return (resultado: ResultadoFactura.invalida, factura: null);
    }

    final fecha = _extraer(texto, 'fechaEmision') ?? '';
    final partes = RegExp(
      r'^(\d{1,4})[-/](\d{1,2})[-/](\d{1,4})',
    ).firstMatch(fecha);
    if (mesPermitido != null || anioPermitido != null) {
      if (partes == null) {
        return (resultado: ResultadoFactura.invalida, factura: null);
      }
      final primero = int.tryParse(partes.group(1)!);
      final segundo = int.tryParse(partes.group(2)!);
      final tercero = int.tryParse(partes.group(3)!);
      final anio = partes.group(1)!.length == 4 ? primero : tercero;
      final mes = segundo;
      if ((mesPermitido != null && mes != mesPermitido) ||
          (anioPermitido != null && anio != anioPermitido)) {
        return (resultado: ResultadoFactura.mesIncorrecto, factura: null);
      }
    }

    final factura = Factura(
      cliente: _extraer(texto, 'razonSocialComprador') ?? 'CLIENTE GENERAL',
      nombreComercial: _extraerNombreComercial(texto),
      fecha: fecha,
      secuencial: secuencial,
      total: _parsearMonto(_extraer(texto, 'importeTotal')),
      identificacionComprador: _normalizarIdentificacion(
        _extraer(texto, 'identificacionComprador') ?? '',
      ),
      tipoIdentificacionComprador:
          (_extraer(texto, 'tipoIdentificacionComprador') ?? '').trim(),
      direccionComprador: _extraerDireccionComprador(texto),
      telefonoComprador: _extraerContactoAdicional(
        texto,
        const {'telefono', 'celular'},
        _limpiarTelefono,
      ),
      correoComprador: _extraerContactoAdicional(
        texto,
        const {'email', 'e-mail', 'correo'},
        _limpiarCorreo,
      ),
    );
    return (resultado: ResultadoFactura.agregada, factura: factura);
  }

  void registrar(Factura factura) => _registrar(factura);

  String? referenciaDesdeTexto(String texto) => _extraer(texto, 'secuencial');

  void _registrar(Factura factura) {
    final secuencial = factura.secuencial;
    final referenciaSinCeros = int.tryParse(secuencial)?.toString();
    _facturas[secuencial] = factura;
    if (referenciaSinCeros != null) _facturas[referenciaSinCeros] = factura;
  }

  String _extraerNombreComercial(String texto) {
    final direccion = _extraer(texto, 'direccionComprador');
    if (direccion == null) return '';
    final separador = direccion.indexOf('|');
    if (separador == -1) return '';
    return direccion
        .substring(separador + 1)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _extraerDireccionComprador(String texto) {
    final valor = _extraer(texto, 'direccionComprador');
    if (valor == null) return '';
    return _limpiarTexto(valor.split('|').first);
  }

  String _extraerContactoAdicional(
    String texto,
    Set<String> nombres,
    String Function(String) limpiar,
  ) {
    final bloque = RegExp(
      r'<(?:[\w-]+:)?infoAdicional(?:\s[^>]*)?>(.*?)</(?:[\w-]+:)?infoAdicional\s*>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(texto)?.group(1);
    if (bloque == null) return '';
    final expresion = RegExp(
      r'''<(?:[\w-]+:)?campoAdicional\b[^>]*\bnombre\s*=\s*(["'])(.*?)\1[^>]*>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</(?:[\w-]+:)?campoAdicional\s*>''',
      caseSensitive: false,
      dotAll: true,
    );
    for (final coincidencia in expresion.allMatches(bloque)) {
      final nombre = _normalizarNombreCampo(
        _decodificarXml(coincidencia.group(2) ?? ''),
      );
      if (!nombres.contains(nombre)) continue;
      final valor = limpiar(_decodificarXml(coincidencia.group(3) ?? ''));
      if (valor.isNotEmpty) return valor;
    }
    return '';
  }

  String _normalizarNombreCampo(String valor) {
    const reemplazos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
    };
    var normalizado = valor.toLowerCase();
    reemplazos.forEach((origen, destino) {
      normalizado = normalizado.replaceAll(origen, destino);
    });
    return normalizado.replaceAll(RegExp(r'\s+'), '').trim();
  }

  String _limpiarTexto(String valor) => valor
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _limpiarTelefono(String valor) {
    final limpio = _limpiarTexto(valor);
    if (!RegExp(r'^[+0-9\s().-]+$').hasMatch(limpio) ||
        '+'.allMatches(limpio).length > 1) {
      return '';
    }
    final digitos = limpio.replaceAll(RegExp(r'\D'), '');
    if (digitos.length < 7 || digitos.length > 15) return '';
    return limpio.contains('+') ? '+$digitos' : digitos;
  }

  String _limpiarCorreo(String valor) {
    final limpio = _limpiarTexto(valor).toLowerCase();
    if (limpio.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(limpio)) {
      return '';
    }
    return limpio;
  }

  String? _extraer(String texto, String etiqueta) {
    final expresion = RegExp(
      '<(?:[\\w-]+:)?$etiqueta(?:\\s[^>]*)?>(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?</(?:[\\w-]+:)?$etiqueta\\s*>',
      caseSensitive: false,
      dotAll: true,
    );
    final valor = expresion.firstMatch(texto)?.group(1)?.trim();
    return valor == null ? null : _decodificarXml(valor);
  }

  /// Keeps leading zeroes while removing formatting punctuation consistently.
  String _normalizarIdentificacion(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  String _decodificarXml(String valor) => valor
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");

  double _parsearMonto(String? valor) {
    if (valor == null) return 0;
    return double.tryParse(valor.replaceAll(',', '.')) ?? 0;
  }
}
