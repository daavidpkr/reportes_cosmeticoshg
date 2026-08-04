class Factura {
  const Factura({
    required this.cliente,
    required this.nombreComercial,
    required this.fecha,
    required this.secuencial,
    required this.total,
  });

  final String cliente;
  final String nombreComercial;
  final String fecha;
  final String secuencial;
  final double total;
}
