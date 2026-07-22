class MetodoPagoModel {
  final String metodoPagoId;
  final String nombre;
  final String descripcion;
  final bool requiereReferencia;
  final bool activo;

  const MetodoPagoModel({
    required this.metodoPagoId,
    required this.nombre,
    this.descripcion = '',
    required this.requiereReferencia,
    this.activo = true,
  });

  factory MetodoPagoModel.fromJson(Map<String, dynamic> j) => MetodoPagoModel(
    metodoPagoId:       j['metodoPagoId']?.toString() ?? '',
    nombre:             j['nombre']?.toString() ?? '',
    descripcion:        j['descripcion']?.toString() ?? '',
    requiereReferencia: j['requiereReferencia'] ?? false,
    activo:             j['activo'] ?? true,
  );
}

class ClienteModel {
  final String clienteId;
  final String nombre;
  final String cedulaRuc;
  final String? email;
  final String? telefono;
  final String? direccion;

  const ClienteModel({
    required this.clienteId,
    required this.nombre,
    required this.cedulaRuc,
    this.email,
    this.telefono,
    this.direccion,
  });

  factory ClienteModel.fromJson(Map<String, dynamic> j) => ClienteModel(
    clienteId: j['clienteId']?.toString() ?? '',
    nombre:    j['nombre']?.toString() ?? '',
    cedulaRuc: j['cedulaRuc']?.toString() ?? '',
    email:     j['email']?.toString(),
    telefono:  j['telefono']?.toString(),
    direccion: j['direccion']?.toString(),
  );

  /// El SRI exige email en la factura electrónica; sin él, el backend usa
  /// el email de la sucursal como respaldo.
  bool get tieneEmail => email != null && email!.trim().isNotEmpty;
}

/// Línea vendida dentro de un comprobante emitido.
class ItemVendidoModel {
  final String nombre;
  final int cantidad;
  final double subtotal;

  const ItemVendidoModel({required this.nombre, required this.cantidad, required this.subtotal});

  factory ItemVendidoModel.fromJson(Map<String, dynamic> j) => ItemVendidoModel(
    nombre:   j['nombre']?.toString() ?? '',
    cantidad: (j['cantidad'] as num?)?.toInt() ?? 0,
    subtotal: FacturaModel._toDouble(j['subtotal']),
  );
}

/// Pago registrado en un comprobante.
class PagoModel {
  final String nombreMetodoPago;
  final double monto;

  const PagoModel({required this.nombreMetodoPago, required this.monto});

  factory PagoModel.fromJson(Map<String, dynamic> j) => PagoModel(
    nombreMetodoPago: j['nombreMetodoPago']?.toString() ?? '',
    monto:            FacturaModel._toDouble(j['monto']),
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
  final List<ItemVendidoModel> items;
  final List<PagoModel> pagos;

  // Cabecera del comprobante
  final String nombreRestaurant;
  final String nombreSucursal;
  final String? razonSocial;
  final String? rucSucursal;
  final String? direccionSucursal;
  final String? telefonoSucursal;

  // Facturación electrónica SRI (null = no enviada al SRI)
  final String? sriEstado; // PROCESANDO | AUTORIZADA | RECHAZADA | ERROR
  final String? sriClaveAcceso;
  final String? sriAutorizacion;
  final String? sriSecuencial;
  final String? sriMensaje;

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
    this.items = const [],
    this.pagos = const [],
    this.nombreRestaurant = '',
    this.nombreSucursal = '',
    this.razonSocial,
    this.rucSucursal,
    this.direccionSucursal,
    this.telefonoSucursal,
    this.sriEstado,
    this.sriClaveAcceso,
    this.sriAutorizacion,
    this.sriSecuencial,
    this.sriMensaje,
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
    items: ((j['items'] as List?) ?? []).map((e) => ItemVendidoModel.fromJson(e)).toList(),
    pagos: ((j['pagos'] as List?) ?? []).map((e) => PagoModel.fromJson(e)).toList(),
    nombreRestaurant:  j['nombreRestaurant']?.toString() ?? '',
    nombreSucursal:    j['nombreSucursal']?.toString() ?? '',
    razonSocial:       j['razonSocial']?.toString(),
    rucSucursal:       j['rucSucursal']?.toString(),
    direccionSucursal: j['direccionSucursal']?.toString(),
    telefonoSucursal:  j['telefonoSucursal']?.toString(),
    sriEstado:         j['sriEstado']?.toString(),
    sriClaveAcceso:    j['sriClaveAcceso']?.toString(),
    sriAutorizacion:   j['sriAutorizacion']?.toString(),
    sriSecuencial:     j['sriSecuencial']?.toString(),
    sriMensaje:        j['sriMensaje']?.toString(),
  );

  /// Con cédula/RUC de cliente es factura; sin cliente es recibo
  /// (consumidor final).
  bool get esFactura => cedulaRucCliente?.isNotEmpty ?? false;

  bool get isAnulada => estado == 'ANULADA';

  /// True si el comprobante fue (o intentó ser) emitido electrónicamente.
  bool get tieneSri => sriEstado != null && sriEstado!.isNotEmpty;
  bool get sriAutorizada => sriEstado == 'AUTORIZADA';

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
