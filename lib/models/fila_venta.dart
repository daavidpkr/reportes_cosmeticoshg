class Abono {
  Abono({this.valor = 0, this.comentario = ''});

  double valor;
  String comentario;
}

class FilaVenta {
  FilaVenta({
    required this.numero,
    this.referencia = '',
    this.cliente = '',
    this.nombreComercial = '',
    this.fecha = '',
    this.numeroFactura = '',
    this.vendedor = '',
    this.esmalte = 0,
    this.venta = 0,
    List<Abono>? abonos,
  }) : abonos = abonos ?? [Abono(), Abono()];

  final int numero;
  String referencia;
  String cliente;
  String nombreComercial;
  String fecha;
  String numeroFactura;
  String vendedor;
  int esmalte;
  double venta;
  final List<Abono> abonos;

  double get totalAbonos => abonos.fold(0, (suma, abono) => suma + abono.valor);
  double get saldo => venta - totalAbonos;
  bool get pagada => venta > 0 && saldo <= 0.005;
  bool get tieneDatos =>
      venta > 0 || cliente.isNotEmpty || referencia.isNotEmpty;
}
