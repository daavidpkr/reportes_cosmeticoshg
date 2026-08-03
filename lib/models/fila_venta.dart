class FilaVenta {
  FilaVenta({
    required this.numero,
    this.referencia = '',
    this.cliente = '',
    this.fecha = '',
    this.numeroFactura = '',
    this.esmalte = 0,
    this.venta = 0,
    this.abono1 = 0,
    this.comentario1 = '',
    this.abono2 = 0,
    this.comentario2 = '',
  });

  final int numero;
  String referencia;
  String cliente;
  String fecha;
  String numeroFactura;
  double esmalte;
  double venta;
  double abono1;
  String comentario1;
  double abono2;
  String comentario2;

  double get totalAbonos => abono1 + abono2;
  double get saldo => venta - totalAbonos;
  bool get tieneDatos =>
      venta > 0 || cliente.isNotEmpty || referencia.isNotEmpty;
}
