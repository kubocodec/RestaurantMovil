/// Resumen general de un período (`/api/reportes/resumen-periodo`): platos
/// más y menos vendidos, sin ventas, horarios, métodos de pago, meseros y
/// pérdidas, comparado con el período anterior de igual duración.
class ResumenPeriodoModel {
  final String alcance;
  final DateTime desde;
  final DateTime hasta;
  final DateTime desdeAnterior;
  final DateTime hastaAnterior;
  final TotalesPeriodo actual;
  final TotalesPeriodo anterior;
  final List<PlatoVentaModel> platos;
  final List<PlatoSinVentaModel> sinVenta;
  final List<VentaHoraModel> porHora;
  /// Cuántos lunes (0) … domingos (6) tiene el período.
  final List<int> diasDelPeriodo;
  final List<VentaTipoModel> porTipo;
  final List<MontoMetodoModel> metodosPago;
  final List<VentaMeseroModel> meseros;
  final int ordenesAnuladas;
  final double valorAnulado;

  const ResumenPeriodoModel({
    required this.alcance,
    required this.desde,
    required this.hasta,
    required this.desdeAnterior,
    required this.hastaAnterior,
    required this.actual,
    required this.anterior,
    required this.platos,
    required this.sinVenta,
    required this.porHora,
    required this.diasDelPeriodo,
    required this.porTipo,
    required this.metodosPago,
    required this.meseros,
    required this.ordenesAnuladas,
    required this.valorAnulado,
  });

  factory ResumenPeriodoModel.fromJson(Map<String, dynamic> j) {
    List<T> lista<T>(String k, T Function(Map<String, dynamic>) f) =>
        ((j[k] as List?) ?? []).map((e) => f(e as Map<String, dynamic>)).toList();
    final dias = ((j['diasDelPeriodo'] as List?) ?? []).map((e) => (e as num).toInt()).toList();
    return ResumenPeriodoModel(
      alcance:        j['alcance']?.toString() ?? '',
      desde:          _fecha(j['desde']),
      hasta:          _fecha(j['hasta']),
      desdeAnterior:  _fecha(j['desdeAnterior']),
      hastaAnterior:  _fecha(j['hastaAnterior']),
      actual:         TotalesPeriodo.fromJson(j['actual'] as Map<String, dynamic>? ?? const {}),
      anterior:       TotalesPeriodo.fromJson(j['anterior'] as Map<String, dynamic>? ?? const {}),
      platos:         lista('platos', PlatoVentaModel.fromJson),
      sinVenta:       lista('sinVenta', PlatoSinVentaModel.fromJson),
      porHora:        lista('porHora', VentaHoraModel.fromJson),
      diasDelPeriodo: dias.length == 7 ? dias : List.filled(7, 0),
      porTipo:        lista('porTipo', VentaTipoModel.fromJson),
      metodosPago:    lista('metodosPago', MontoMetodoModel.fromJson),
      meseros:        lista('meseros', VentaMeseroModel.fromJson),
      ordenesAnuladas: _i(j['ordenesAnuladas']),
      valorAnulado:   _d(j['valorAnulado']),
    );
  }
}

class TotalesPeriodo {
  final double ventas;
  final double propinas;
  final double iva;
  /// Descuentos sin contar las cortesías.
  final double descuentos;
  final int comprobantes;
  final int mesas;
  final int mesasEnSala;
  final int personas;
  final int mesasConPersonas;
  final double ventasConPersonas;
  final double costo;
  /// 0 = el local no registra costos: no se muestra la ganancia.
  final int lineasConCosto;
  final int unidadesCortesia;
  final double valorCortesias;

  const TotalesPeriodo({
    required this.ventas,
    required this.propinas,
    required this.iva,
    required this.descuentos,
    required this.comprobantes,
    required this.mesas,
    required this.mesasEnSala,
    required this.personas,
    required this.mesasConPersonas,
    required this.ventasConPersonas,
    required this.costo,
    required this.lineasConCosto,
    required this.unidadesCortesia,
    required this.valorCortesias,
  });

  factory TotalesPeriodo.fromJson(Map<String, dynamic> j) => TotalesPeriodo(
    ventas:            _d(j['ventas']),
    propinas:          _d(j['propinas']),
    iva:               _d(j['iva']),
    descuentos:        _d(j['descuentos']),
    comprobantes:      _i(j['comprobantes']),
    mesas:             _i(j['mesas']),
    mesasEnSala:       _i(j['mesasEnSala']),
    personas:          _i(j['personas']),
    mesasConPersonas:  _i(j['mesasConPersonas']),
    ventasConPersonas: _d(j['ventasConPersonas']),
    costo:             _d(j['costo']),
    lineasConCosto:    _i(j['lineasConCosto']),
    unidadesCortesia:  _i(j['unidadesCortesia']),
    valorCortesias:    _d(j['valorCortesias']),
  );

  /// Igual que el resumen diario: sin propinas, que son del mesero.
  double get ventasSinPropina => ventas - propinas;
  double? get ticketPromedio => comprobantes > 0 ? ventasSinPropina / comprobantes : null;
  double? get promedioPorMesa => mesas > 0 ? ventasSinPropina / mesas : null;
  double? get promedioPorPersona => personas > 0 ? ventasConPersonas / personas : null;
  bool get tieneCostos => lineasConCosto > 0;
  double get gananciaEstimada => ventas - iva - propinas - costo;
}

class PlatoVentaModel {
  final String platoId;
  final String nombre;
  final String categoria;
  final int unidades;
  /// Con IVA, a precio de carta.
  final double ventas;
  final double ventasSinIva;
  /// Costo unitario registrado; null si no tiene.
  final double? costo;
  final int unidadesCortesia;

  const PlatoVentaModel({
    required this.platoId,
    required this.nombre,
    required this.categoria,
    required this.unidades,
    required this.ventas,
    required this.ventasSinIva,
    required this.costo,
    required this.unidadesCortesia,
  });

  factory PlatoVentaModel.fromJson(Map<String, dynamic> j) => PlatoVentaModel(
    platoId:          j['platoId']?.toString() ?? '',
    nombre:           j['nombre']?.toString() ?? '',
    categoria:        j['categoria']?.toString() ?? '',
    unidades:         _i(j['unidades']),
    ventas:           _d(j['ventas']),
    ventasSinIva:     _d(j['ventasSinIva']),
    costo:            j['costo'] == null ? null : _d(j['costo']),
    unidadesCortesia: _i(j['unidadesCortesia']),
  );

  /// Lo que deja el plato: ventas sin IVA menos su costo. null sin costo.
  double? get ganancia =>
      (costo != null && costo! > 0) ? ventasSinIva - costo! * unidades : null;
}

class PlatoSinVentaModel {
  final String platoId;
  final String nombre;
  final String categoria;
  final bool disponible;

  const PlatoSinVentaModel({
    required this.platoId,
    required this.nombre,
    required this.categoria,
    required this.disponible,
  });

  factory PlatoSinVentaModel.fromJson(Map<String, dynamic> j) => PlatoSinVentaModel(
    platoId:    j['platoId']?.toString() ?? '',
    nombre:     j['nombre']?.toString() ?? '',
    categoria:  j['categoria']?.toString() ?? '',
    disponible: j['disponible'] != false,
  );
}

class VentaHoraModel {
  /// 1 = lunes … 7 = domingo.
  final int dia;
  final int hora;
  final int ordenes;
  final double ventas;

  const VentaHoraModel({required this.dia, required this.hora, required this.ordenes, required this.ventas});

  factory VentaHoraModel.fromJson(Map<String, dynamic> j) => VentaHoraModel(
    dia:     _i(j['dia']),
    hora:    _i(j['hora']),
    ordenes: _i(j['ordenes']),
    ventas:  _d(j['ventas']),
  );
}

class VentaTipoModel {
  final String tipo;
  final int ordenes;
  final double ventas;

  const VentaTipoModel({required this.tipo, required this.ordenes, required this.ventas});

  factory VentaTipoModel.fromJson(Map<String, dynamic> j) => VentaTipoModel(
    tipo:    j['tipo']?.toString() ?? '',
    ordenes: _i(j['ordenes']),
    ventas:  _d(j['ventas']),
  );
}

class MontoMetodoModel {
  final String metodo;
  final double monto;

  const MontoMetodoModel({required this.metodo, required this.monto});

  factory MontoMetodoModel.fromJson(Map<String, dynamic> j) => MontoMetodoModel(
    metodo: j['metodo']?.toString() ?? '',
    monto:  _d(j['monto']),
  );
}

class VentaMeseroModel {
  final String nombre;
  final int ordenes;
  final double ventas;
  final double propinas;

  const VentaMeseroModel({required this.nombre, required this.ordenes, required this.ventas, required this.propinas});

  factory VentaMeseroModel.fromJson(Map<String, dynamic> j) => VentaMeseroModel(
    nombre:   j['nombre']?.toString() ?? '',
    ordenes:  _i(j['ordenes']),
    ventas:   _d(j['ventas']),
    propinas: _d(j['propinas']),
  );
}

double _d(dynamic v) => v == null ? 0.0 : (v as num).toDouble();
int _i(dynamic v) => v == null ? 0 : (v as num).toInt();
DateTime _fecha(dynamic v) => DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
