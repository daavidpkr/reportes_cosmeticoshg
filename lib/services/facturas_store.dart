import '../models/factura.dart';

class FacturasStore {
  FacturasStore._();

  static final FacturasStore instance = FacturasStore._();
  final Map<String, Factura> _facturas = {};

  int get cantidad => _facturas.values.toSet().length;

  Factura? buscar(String referencia) => _facturas[referencia.trim()];

  void limpiar() => _facturas.clear();

  bool agregarDesdeTexto(String texto) {
    final secuencial = _extraer(texto, 'secuencial');
    if (secuencial == null || secuencial.isEmpty) return false;

    final factura = Factura(
      cliente: _extraer(texto, 'razonSocialComprador') ?? 'CLIENTE GENERAL',
      nombreComercial: _extraerNombreComercial(texto),
      fecha: _extraer(texto, 'fechaEmision') ?? '',
      secuencial: secuencial,
      total: _parsearMonto(_extraer(texto, 'importeTotal')),
    );
    final referenciaSinCeros = int.tryParse(secuencial)?.toString();
    _facturas[secuencial] = factura;
    if (referenciaSinCeros != null) _facturas[referenciaSinCeros] = factura;
    return true;
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
