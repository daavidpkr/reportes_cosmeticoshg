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

  String? _extraer(String texto, String etiqueta) {
    final expresion = RegExp(
      '<(?:[\\w-]+:)?$etiqueta(?:\\s[^>]*)?>(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?</(?:[\\w-]+:)?$etiqueta\\s*>',
      caseSensitive: false,
      dotAll: true,
    );
    final valor = expresion.firstMatch(texto)?.group(1)?.trim();
    return valor == null ? null : _decodificarXml(valor);
  }

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
