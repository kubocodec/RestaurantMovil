class DetalleOrdenModel {
  final String ordenDetalleId;
  final String platoId;
  final String nombrePlato;
  final int cantidad;
  final double precioUnitario;
  final double subtotal;
  final String estado;
  final String tipoServicio;
  final String? observaciones;
  final bool facturado;
  final int cantidadFacturada;
  final String? impresoraNombre;
  final String? impresoraIp;
  final int? impresoraPuerto;
  final String? impresoraMac;

  const DetalleOrdenModel({
    required this.ordenDetalleId,
    required this.platoId,
    required this.nombrePlato,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
    required this.estado,
    required this.tipoServicio,
    this.observaciones,
    required this.facturado,
    this.cantidadFacturada = 0,
    this.impresoraNombre,
    this.impresoraIp,
    this.impresoraPuerto,
    this.impresoraMac,
  });

  factory DetalleOrdenModel.fromJson(Map<String, dynamic> j) => DetalleOrdenModel(
    ordenDetalleId: j['ordenDetalleId']?.toString() ?? '',
    platoId:        j['platoId']?.toString() ?? '',
    nombrePlato:    j['nombrePlato']?.toString() ?? '',
    cantidad:       (j['cantidad'] as num?)?.toInt() ?? 1,
    precioUnitario: _toDouble(j['precioUnitario']),
    subtotal:       _toDouble(j['subtotal']),
    estado:         j['estado']?.toString() ?? 'PENDIENTE',
    tipoServicio:   j['tipoServicio']?.toString() ?? 'EN_MESA',
    observaciones:  j['observaciones']?.toString(),
    facturado:      j['facturado'] ?? false,
    cantidadFacturada: (j['cantidadFacturada'] as num?)?.toInt() ?? 0,
    impresoraNombre: j['impresoraNombre']?.toString(),
    impresoraIp:     j['impresoraIp']?.toString(),
    impresoraPuerto: (j['impresoraPuerto'] as num?)?.toInt(),
    impresoraMac:    j['impresoraMac']?.toString(),
  );

  /// Unidades que faltan por cobrar (cuentas divididas).
  int get cantidadPendiente => facturado ? 0 : cantidad - cantidadFacturada;

  /// Monto pendiente de cobro de esta línea.
  double get subtotalPendiente => precioUnitario * cantidadPendiente;

  bool get isPendiente     => estado == 'PENDIENTE' || estado == 'ENVIADO';
  bool get isEnPreparacion => estado == 'EN_PREPARACION';
  bool get isListo         => estado == 'LISTO';
  bool get isEntregado     => estado == 'ENTREGADO';

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}

class OrdenModel {
  final String ordenId;
  final int numeroOrden;
  final String mesaId;
  final String numeroMesa;
  final String sucursalId;
  final String estado;
  final String tipoOrden;
  final String tipoOrigen;
  final String? observaciones;
  final DateTime fechaCreacion;
  final List<DetalleOrdenModel> detalles;

  const OrdenModel({
    required this.ordenId,
    required this.numeroOrden,
    required this.mesaId,
    required this.numeroMesa,
    required this.sucursalId,
    required this.estado,
    required this.tipoOrden,
    required this.tipoOrigen,
    this.observaciones,
    required this.fechaCreacion,
    required this.detalles,
  });

  factory OrdenModel.fromJson(Map<String, dynamic> j) {
    final List detallesRaw = j['detalles'] ?? [];
    return OrdenModel(
      ordenId:       j['ordenId']?.toString() ?? '',
      numeroOrden:   (j['numeroOrden'] as num?)?.toInt() ?? 0,
      mesaId:        j['mesaId']?.toString() ?? '',
      numeroMesa:    j['numeroMesa']?.toString() ?? '',
      sucursalId:    j['sucursalId']?.toString() ?? '',
      estado:        j['estado']?.toString() ?? 'ABIERTA',
      tipoOrden:     j['tipoOrden']?.toString() ?? 'EN_MESA',
      tipoOrigen:    j['tipoOrigen']?.toString() ?? 'MESERO',
      observaciones: j['observaciones']?.toString(),
      fechaCreacion: DateTime.tryParse(j['fechaCreacion']?.toString() ?? '') ?? DateTime.now(),
      detalles:      detallesRaw.map((d) => DetalleOrdenModel.fromJson(d)).toList(),
    );
  }

  bool get esParaLlevar => tipoOrden == 'PARA_LLEVAR';

  /// Dónde mostrar la orden: el número de mesa, o "Para llevar" cuando
  /// no ocupa mesa (el backend no envía numeroMesa en ese caso).
  String get lugar => numeroMesa.isNotEmpty ? numeroMesa : 'Para llevar';

  double get total => detalles.fold(0.0, (s, d) => s + d.subtotal);

  List<DetalleOrdenModel> get detallesNoFacturados =>
      detalles.where((d) => d.cantidadPendiente > 0 && d.estado != 'CANCELADO').toList();

  List<DetalleOrdenModel> get detallesPendientesCocina =>
      detalles.where((d) => d.isPendiente).toList();
}
