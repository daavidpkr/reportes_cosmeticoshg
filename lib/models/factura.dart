class Factura {
  const Factura({
    required this.cliente,
    required this.nombreComercial,
    required this.fecha,
    required this.secuencial,
    required this.total,
    this.identificacionComprador = '',
    this.tipoIdentificacionComprador = '',
  });

  final String cliente;
  final String nombreComercial;
  final String fecha;
  final String secuencial;
  final double total;

  /// Internal customer identity. It is deliberately never rendered in UI/PDF.
  final String identificacionComprador;
  final String tipoIdentificacionComprador;

  Map<String, dynamic> toJson() => {
        'cliente': cliente,
        'nombreComercial': nombreComercial,
        'fecha': fecha,
        'secuencial': secuencial,
        'total': total,
        'identificacionComprador': identificacionComprador,
        'tipoIdentificacionComprador': tipoIdentificacionComprador,
      };

  factory Factura.fromJson(Map<String, dynamic> json) => Factura(
        cliente: json['cliente'] as String? ?? '',
        nombreComercial: json['nombreComercial'] as String? ?? '',
        fecha: json['fecha'] as String? ?? '',
        secuencial: json['secuencial'] as String? ?? '',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        identificacionComprador:
            json['identificacionComprador'] as String? ?? '',
        tipoIdentificacionComprador:
            json['tipoIdentificacionComprador'] as String? ?? '',
      );
}

class FacturaAsignada {
  const FacturaAsignada({
    required this.factura,
    required this.vendedor,
    this.paymentTermDays,
  });

  final Factura factura;
  final String vendedor;

  /// Only supplied for a customer whose canonical term is missing.
  final int? paymentTermDays;
}
