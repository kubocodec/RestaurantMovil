class MetodoPagoModel {
  final String metodoPagoId;
  final String nombre;
  final bool requiereReferencia;

  const MetodoPagoModel({
    required this.metodoPagoId,
    required this.nombre,
    required this.requiereReferencia,
  });

  factory MetodoPagoModel.fromJson(Map<String, dynamic> j) => MetodoPagoModel(
    metodoPagoId:       j['metodoPagoId']?.toString() ?? '',
    nombre:             j['nombre']?.toString() ?? '',
    requiereReferencia: j['requiereReferencia'] ?? false,
  );
}

class ClienteModel {
  final String clienteId;
  final String nombre;
  final String cedulaRuc;
  final String? email;
  final String? telefono;

  const ClienteModel({
    required this.clienteId,
    required this.nombre,
    required this.cedulaRuc,
    this.email,
    this.telefono,
  });

  factory ClienteModel.fromJson(Map<String, dynamic> j) => ClienteModel(
    clienteId: j['clienteId']?.toString() ?? '',
    nombre:    j['nombre']?.toString() ?? '',
    cedulaRuc: j['cedulaRuc']?.toString() ?? '',
    email:     j['email']?.toString(),
    telefono:  j['telefono']?.toString(),
  );
}

class FacturaModel {
  final String facturaVentaId;
  final String numeroFactura;
  final String ordenId;
  final int numeroOrden;
  final String estado;
  final double subtotal;
  final double iva;
  final double total;
  final String? nombreCliente;
  final DateTime fecha;

  const FacturaModel({
    required this.facturaVentaId,
    required this.numeroFactura,
    required this.ordenId,
    required this.numeroOrden,
    required this.estado,
    required this.subtotal,
    required this.iva,
    required this.total,
    this.nombreCliente,
    required this.fecha,
  });

  factory FacturaModel.fromJson(Map<String, dynamic> j) => FacturaModel(
    facturaVentaId: j['facturaVentaId']?.toString() ?? '',
    numeroFactura:  j['numeroFactura']?.toString() ?? '',
    ordenId:        j['ordenId']?.toString() ?? '',
    numeroOrden:    (j['numeroOrden'] ?? 0) as int,
    estado:         j['estado']?.toString() ?? '',
    subtotal:       _toDouble(j['subtotal']),
    iva:            _toDouble(j['iva']),
    total:          _toDouble(j['total']),
    nombreCliente:  j['nombreCliente']?.toString(),
    fecha:          DateTime.tryParse(j['fecha']?.toString() ?? '') ?? DateTime.now(),
  );

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
