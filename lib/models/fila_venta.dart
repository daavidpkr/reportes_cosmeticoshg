class Abono {
  Abono({this.valor = 0, this.comentario = ''});

  double valor;
  String comentario;

  Map<String, dynamic> toJson() => {'valor': valor, 'comentario': comentario};
  factory Abono.fromJson(Map<String, dynamic> json) => Abono(
        valor: (json['valor'] as num?)?.toDouble() ?? 0,
        comentario: json['comentario'] as String? ?? '',
      );
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

  int numero;
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
      referencia.trim().isNotEmpty ||
      cliente.trim().isNotEmpty ||
      nombreComercial.trim().isNotEmpty ||
      fecha.trim().isNotEmpty ||
      numeroFactura.trim().isNotEmpty ||
      vendedor.trim().isNotEmpty ||
      esmalte != 0 ||
      venta != 0 ||
      abonos.any(
        (abono) => abono.valor != 0 || abono.comentario.trim().isNotEmpty,
      );

  Map<String, dynamic> toJson() => {
        'numero': numero,
        'referencia': referencia,
        'cliente': cliente,
        'nombreComercial': nombreComercial,
        'fecha': fecha,
        'numeroFactura': numeroFactura,
        'vendedor': vendedor,
        'esmalte': esmalte,
        'venta': venta,
        'abonos': abonos.map((item) => item.toJson()).toList(),
      };

  factory FilaVenta.fromJson(Map<String, dynamic> json) => FilaVenta(
        numero: json['numero'] as int? ?? 1,
        referencia: json['referencia'] as String? ?? '',
        cliente: json['cliente'] as String? ?? '',
        nombreComercial: json['nombreComercial'] as String? ?? '',
        fecha: json['fecha'] as String? ?? '',
        numeroFactura: json['numeroFactura'] as String? ?? '',
        vendedor: json['vendedor'] as String? ?? '',
        esmalte: json['esmalte'] as int? ?? 0,
        venta: (json['venta'] as num?)?.toDouble() ?? 0,
        abonos: (json['abonos'] as List<dynamic>? ?? const [])
            .map((item) => Abono.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}
