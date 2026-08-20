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

  Map<String, dynamic> toJson() => {
        'cliente': cliente,
        'nombreComercial': nombreComercial,
        'fecha': fecha,
        'secuencial': secuencial,
        'total': total,
      };

  factory Factura.fromJson(Map<String, dynamic> json) => Factura(
        cliente: json['cliente'] as String? ?? '',
        nombreComercial: json['nombreComercial'] as String? ?? '',
        fecha: json['fecha'] as String? ?? '',
        secuencial: json['secuencial'] as String? ?? '',
        total: (json['total'] as num?)?.toDouble() ?? 0,
      );
}

class FacturaAsignada {
  const FacturaAsignada({required this.factura, required this.vendedor});

  final Factura factura;
  final String vendedor;
}
