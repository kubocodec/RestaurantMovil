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
  final DateTime fechaApertura;
  final DateTime? fechaCierre;

  const AperturaCajaModel({
    required this.aperturaCierreCajaId,
    required this.cajaId,
    required this.nombreCaja,
    required this.estado,
    required this.montoInicial,
    this.montoFinal,
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
