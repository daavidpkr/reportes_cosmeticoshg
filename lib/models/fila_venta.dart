// Supabase serializa este valor como JSON. Este límite es positivo, cabe en
// PostgreSQL bigint y no pierde precisión cuando Flutter se ejecuta en web.
const int maxNumeroReciboSeguro = 9007199254740991;

String? validarNumeroRecibo(String valor) {
  final limpio = valor.trim();
  if (limpio.isEmpty) return null;
  if (!RegExp(r'^\d+$').hasMatch(limpio)) {
    return 'El número de recibo debe ser un entero mayor que cero.';
  }
  final numero = int.tryParse(limpio);
  if (numero == null || numero > maxNumeroReciboSeguro) {
    return 'El número de recibo debe ser un entero mayor que cero.';
  }
  if (numero == 0) {
    return 'El número de recibo debe ser un entero mayor que cero.';
  }
  return null;
}

String? validarValorAbono(String valor) {
  final numero = double.tryParse(valor.trim().replaceAll(',', '.'));
  if (numero == null || !numero.isFinite || numero <= 0) {
    return 'Ingresa un valor de abono válido mayor que cero';
  }
  return null;
}

class Abono {
  Abono({this.valor = 0, this.numeroRecibo, this.comentario = ''});

  double valor;
  int? numeroRecibo;
  String comentario;

  Map<String, dynamic> toJson() => {
        'valor': valor,
        'numeroRecibo': numeroRecibo,
        'comentario': comentario,
      };
  factory Abono.fromJson(Map<String, dynamic> json) => Abono(
        valor: (json['valor'] as num?)?.toDouble() ?? 0,
        numeroRecibo: (json['numeroRecibo'] as num?)?.toInt(),
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
  bool get anulada => vendedor.trim().toUpperCase() == 'ANULADA';
  bool get pagada => !anulada && venta > 0 && saldo <= 0.005;
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
        (abono) =>
            abono.valor != 0 ||
            abono.numeroRecibo != null ||
            abono.comentario.trim().isNotEmpty,
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
