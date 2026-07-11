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
  final double descuento;
  final double ivaPorcentaje;
  final double iva;
  final double propina;
  final double total;
  final String? nombreCliente;
  final String? cedulaRucCliente;
  final DateTime fecha;

  // Cabecera del comprobante
  final String nombreRestaurant;
  final String nombreSucursal;
  final String? razonSocial;
  final String? rucSucursal;
  final String? direccionSucursal;
  final String? telefonoSucursal;

  const FacturaModel({
    required this.facturaVentaId,
    required this.numeroFactura,
    required this.ordenId,
    required this.numeroOrden,
    required this.estado,
    required this.subtotal,
    this.descuento = 0,
    this.ivaPorcentaje = 0,
    required this.iva,
    this.propina = 0,
    required this.total,
    this.nombreCliente,
    this.cedulaRucCliente,
    required this.fecha,
    this.nombreRestaurant = '',
    this.nombreSucursal = '',
    this.razonSocial,
    this.rucSucursal,
    this.direccionSucursal,
    this.telefonoSucursal,
  });

  factory FacturaModel.fromJson(Map<String, dynamic> j) => FacturaModel(
    facturaVentaId: j['facturaVentaId']?.toString() ?? '',
    numeroFactura:  j['numeroFactura']?.toString() ?? '',
    ordenId:        j['ordenId']?.toString() ?? '',
    numeroOrden:    (j['numeroOrden'] ?? 0) as int,
    estado:         j['estado']?.toString() ?? '',
    subtotal:       _toDouble(j['subtotal']),
    descuento:      _toDouble(j['descuento']),
    ivaPorcentaje:  _toDouble(j['ivaPorcentaje']),
    iva:            _toDouble(j['iva']),
    propina:        _toDouble(j['propina']),
    total:          _toDouble(j['total']),
    nombreCliente:  j['nombreCliente']?.toString(),
    cedulaRucCliente: j['cedulaRucCliente']?.toString(),
    fecha:          DateTime.tryParse(j['fecha']?.toString() ?? '') ?? DateTime.now(),
    nombreRestaurant:  j['nombreRestaurant']?.toString() ?? '',
    nombreSucursal:    j['nombreSucursal']?.toString() ?? '',
    razonSocial:       j['razonSocial']?.toString(),
    rucSucursal:       j['rucSucursal']?.toString(),
    direccionSucursal: j['direccionSucursal']?.toString(),
    telefonoSucursal:  j['telefonoSucursal']?.toString(),
  );

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
