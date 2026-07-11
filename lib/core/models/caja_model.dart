class CajaModel {
  final String cajaId;
  final String nombre;
  final String descripcion;
  final bool activo;

  const CajaModel({
    required this.cajaId,
    required this.nombre,
    required this.descripcion,
    required this.activo,
  });

  factory CajaModel.fromJson(Map<String, dynamic> j) => CajaModel(
    cajaId:      j['cajaId']?.toString() ?? '',
    nombre:      j['nombre']?.toString() ?? '',
    descripcion: j['descripcion']?.toString() ?? '',
    activo:      j['activo'] ?? true,
  );
}

class AperturaCajaModel {
  final String aperturaCierreCajaId;
  final String cajaId;
  final String nombreCaja;
  final String estado;
  final double montoInicial;
  final double? montoFinal;
  final double? montoEsperado;
  final double? diferencia;
  final DateTime fechaApertura;
  final DateTime? fechaCierre;

  const AperturaCajaModel({
    required this.aperturaCierreCajaId,
    required this.cajaId,
    required this.nombreCaja,
    required this.estado,
    required this.montoInicial,
    this.montoFinal,
    this.montoEsperado,
    this.diferencia,
    required this.fechaApertura,
    this.fechaCierre,
  });

  factory AperturaCajaModel.fromJson(Map<String, dynamic> j) => AperturaCajaModel(
    aperturaCierreCajaId: j['aperturaCierreCajaId']?.toString() ?? '',
    cajaId:               j['cajaId']?.toString() ?? '',
    nombreCaja:           j['nombreCaja']?.toString() ?? '',
    estado:               j['estado']?.toString() ?? 'ABIERTA',
    montoInicial:         _toDouble(j['montoInicial']),
    montoFinal:           j['montoFinal'] != null ? _toDouble(j['montoFinal']) : null,
    montoEsperado:        j['montoEsperado'] != null ? _toDouble(j['montoEsperado']) : null,
    diferencia:           j['diferencia'] != null ? _toDouble(j['diferencia']) : null,
    fechaApertura:        DateTime.tryParse(j['fechaApertura']?.toString() ?? '') ?? DateTime.now(),
    fechaCierre:          j['fechaCierre'] != null ? DateTime.tryParse(j['fechaCierre'].toString()) : null,
  );

  bool get isAbierta => estado == 'ABIERTA';

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}

class MovimientoCajaModel {
  final String tipo;   // INGRESO | EGRESO
  final double monto;
  final String concepto;

  const MovimientoCajaModel({
    required this.tipo,
    required this.monto,
    required this.concepto,
  });

  Map<String, dynamic> toJson() => {'tipo': tipo, 'monto': monto, 'concepto': concepto};
}

/// Estado en vivo de la apertura: cuánto debería haber en caja y por qué.
class ResumenCajaModel {
  final double montoInicial;
  final double totalVentas;
  final double totalIngresos;
  final double totalEgresos;
  final double montoEsperado;
  final List<MovimientoItemModel> movimientos;
  final List<VentaPlatoModel> ventasPorPlato;

  const ResumenCajaModel({
    required this.montoInicial,
    required this.totalVentas,
    required this.totalIngresos,
    required this.totalEgresos,
    required this.montoEsperado,
    required this.movimientos,
    required this.ventasPorPlato,
  });

  factory ResumenCajaModel.fromJson(Map<String, dynamic> j) => ResumenCajaModel(
    montoInicial:  AperturaCajaModel._toDouble(j['montoInicial']),
    totalVentas:   AperturaCajaModel._toDouble(j['totalVentas']),
    totalIngresos: AperturaCajaModel._toDouble(j['totalIngresos']),
    totalEgresos:  AperturaCajaModel._toDouble(j['totalEgresos']),
    montoEsperado: AperturaCajaModel._toDouble(j['montoEsperado']),
    movimientos: ((j['movimientos'] as List?) ?? [])
        .map((m) => MovimientoItemModel.fromJson(m))
        .toList(),
    ventasPorPlato: ((j['ventasPorPlato'] as List?) ?? [])
        .map((v) => VentaPlatoModel.fromJson(v))
        .toList(),
  );
}

/// Desglose de lo vendido en el turno: cuántos de cada plato y por cuánto.
class VentaPlatoModel {
  final String plato;
  final int cantidad;
  final double total;

  const VentaPlatoModel({required this.plato, required this.cantidad, required this.total});

  factory VentaPlatoModel.fromJson(Map<String, dynamic> j) => VentaPlatoModel(
    plato:    j['plato']?.toString() ?? '',
    cantidad: (j['cantidad'] as num?)?.toInt() ?? 0,
    total:    AperturaCajaModel._toDouble(j['total']),
  );
}

class MovimientoItemModel {
  final String tipo;
  final double monto;
  final String concepto;
  final String usuario;
  final DateTime fecha;

  const MovimientoItemModel({
    required this.tipo,
    required this.monto,
    required this.concepto,
    required this.usuario,
    required this.fecha,
  });

  bool get esIngreso => tipo == 'INGRESO';

  factory MovimientoItemModel.fromJson(Map<String, dynamic> j) => MovimientoItemModel(
    tipo:     j['tipo']?.toString() ?? '',
    monto:    AperturaCajaModel._toDouble(j['monto']),
    concepto: j['concepto']?.toString() ?? '',
    usuario:  j['usuario']?.toString() ?? '',
    fecha:    DateTime.tryParse(j['fecha']?.toString() ?? '') ?? DateTime.now(),
  );
}
