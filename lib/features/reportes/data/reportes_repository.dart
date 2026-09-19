import '../../../core/models/caja_model.dart';
import '../../../core/models/orden_model.dart';
import '../../../core/network/api_client.dart';

class ResumenDiarioModel {
  final String nombreSucursal;
  final int totalOrdenes;
  final int totalFacturas;
  final double totalVentas;
  final double totalDescuentos;
  final double totalIva;
  final double totalPropinas;
  final double totalNeto;
  final double totalCosto;
  final double gananciaEstimada;
  /// Lo regalado en el día a precio de carta (no está en las ventas).
  final int unidadesCortesia;
  final double valorCortesias;

  const ResumenDiarioModel({
    required this.nombreSucursal,
    required this.totalOrdenes,
    required this.totalFacturas,
    required this.totalVentas,
    required this.totalDescuentos,
    required this.totalIva,
    required this.totalPropinas,
    required this.totalNeto,
    required this.totalCosto,
    required this.gananciaEstimada,
    this.unidadesCortesia = 0,
    this.valorCortesias = 0,
  });

  factory ResumenDiarioModel.fromJson(Map<String, dynamic> j) => ResumenDiarioModel(
    nombreSucursal:   j['nombreSucursal']?.toString() ?? '',
    totalOrdenes:     (j['totalOrdenes'] as num?)?.toInt() ?? 0,
    totalFacturas:    (j['totalFacturas'] as num?)?.toInt() ?? 0,
    totalVentas:      _d(j['totalVentas']),
    totalDescuentos:  _d(j['totalDescuentos']),
    totalIva:         _d(j['totalIva']),
    totalPropinas:    _d(j['totalPropinas']),
    totalNeto:        _d(j['totalNeto']),
    totalCosto:       _d(j['totalCosto']),
    gananciaEstimada: _d(j['gananciaEstimada']),
    unidadesCortesia: (j['unidadesCortesia'] as num?)?.toInt() ?? 0,
    valorCortesias:   _d(j['valorCortesias']),
  );

  static double _d(dynamic v) => v == null ? 0.0 : (v as num).toDouble();
}

/// Reporte de caja del día: agregados de todos los turnos de la sucursal
/// y el detalle completo de cada uno (ingresos, egresos, faltante...).
class ReporteCajasDiaModel {
  final double totalVentas;
  final double totalVentasEfectivo;
  final double totalIngresos;
  final double totalEgresos;
  final double totalEsperado;
  final double totalContado;
  final double totalDiferencia; // negativo = faltante, positivo = sobrante
  final List<CierreDetalladoModel> cierres;

  const ReporteCajasDiaModel({
    required this.totalVentas,
    required this.totalVentasEfectivo,
    required this.totalIngresos,
    required this.totalEgresos,
    required this.totalEsperado,
    required this.totalContado,
    required this.totalDiferencia,
    required this.cierres,
  });

  factory ReporteCajasDiaModel.fromJson(Map<String, dynamic> j) => ReporteCajasDiaModel(
    totalVentas:         _d(j['totalVentas']),
    totalVentasEfectivo: _d(j['totalVentasEfectivo']),
    totalIngresos:       _d(j['totalIngresos']),
    totalEgresos:        _d(j['totalEgresos']),
    totalEsperado:       _d(j['totalEsperado']),
    totalContado:        _d(j['totalContado']),
    totalDiferencia:     _d(j['totalDiferencia']),
    cierres: ((j['cierres'] as List?) ?? [])
        .map((c) => CierreDetalladoModel.fromJson(c))
        .toList(),
  );

  static double _d(dynamic v) => v == null ? 0.0 : (v as num).toDouble();
}

/// Cuánto vendió una sucursal en el período consultado.
class VentaSucursalModel {
  final String sucursalId;
  final String nombreSucursal;
  final double totalVentas;
  final int totalFacturas;
  final int totalOrdenes;
  final double gananciaEstimada;

  const VentaSucursalModel({
    required this.sucursalId,
    required this.nombreSucursal,
    required this.totalVentas,
    required this.totalFacturas,
    required this.totalOrdenes,
    required this.gananciaEstimada,
  });

  factory VentaSucursalModel.fromJson(Map<String, dynamic> j) => VentaSucursalModel(
    sucursalId:       j['sucursalId']?.toString() ?? '',
    nombreSucursal:   j['nombreSucursal']?.toString() ?? '',
    totalVentas:      ReporteCajasDiaModel._d(j['totalVentas']),
    totalFacturas:    (j['totalFacturas'] as num?)?.toInt() ?? 0,
    totalOrdenes:     (j['totalOrdenes'] as num?)?.toInt() ?? 0,
    gananciaEstimada: ReporteCajasDiaModel._d(j['gananciaEstimada']),
  );
}

/// Comparativo de la empresa: ventas por sucursal + totales del período.
class ReporteVentasSucursalesModel {
  final String nombreRestaurant;
  final double totalVentas;
  final int totalFacturas;
  final int totalOrdenes;
  final double totalGananciaEstimada;
  final List<VentaSucursalModel> sucursales;

  const ReporteVentasSucursalesModel({
    required this.nombreRestaurant,
    required this.totalVentas,
    required this.totalFacturas,
    required this.totalOrdenes,
    required this.totalGananciaEstimada,
    required this.sucursales,
  });

  factory ReporteVentasSucursalesModel.fromJson(Map<String, dynamic> j) =>
      ReporteVentasSucursalesModel(
        nombreRestaurant:      j['nombreRestaurant']?.toString() ?? '',
        totalVentas:           ReporteCajasDiaModel._d(j['totalVentas']),
        totalFacturas:         (j['totalFacturas'] as num?)?.toInt() ?? 0,
        totalOrdenes:          (j['totalOrdenes'] as num?)?.toInt() ?? 0,
        totalGananciaEstimada: ReporteCajasDiaModel._d(j['totalGananciaEstimada']),
        sucursales: ((j['sucursales'] as List?) ?? [])
            .map((s) => VentaSucursalModel.fromJson(s))
            .toList(),
      );
}

/// Órdenes anuladas del período: cada una con motivo, quién la anuló y
/// el detalle completo de lo que tenía pedido.
class ReporteOrdenesAnuladasModel {
  final String nombreSucursal;
  final int totalOrdenes;
  final double totalAnulado;
  final List<OrdenModel> ordenes;

  const ReporteOrdenesAnuladasModel({
    required this.nombreSucursal,
    required this.totalOrdenes,
    required this.totalAnulado,
    required this.ordenes,
  });

  factory ReporteOrdenesAnuladasModel.fromJson(Map<String, dynamic> j) =>
      ReporteOrdenesAnuladasModel(
        nombreSucursal: j['nombreSucursal']?.toString() ?? '',
        totalOrdenes:   (j['totalOrdenes'] as num?)?.toInt() ?? 0,
        totalAnulado:   ReporteCajasDiaModel._d(j['totalAnulado']),
        ordenes: ((j['ordenes'] as List?) ?? [])
            .map((o) => OrdenModel.fromJson(o))
            .toList(),
      );
}

/// Una cortesía del período: qué se regaló, cuánto valía, por qué y quién.
class CortesiaItemModel {
  final DateTime fecha;
  final int? numeroOrden;
  final String lugar;
  final String plato;
  final int cantidad;
  final double valor;
  final String? motivo;
  final String? autorizadaPor;
  final bool cobrada;

  const CortesiaItemModel({
    required this.fecha,
    this.numeroOrden,
    required this.lugar,
    required this.plato,
    required this.cantidad,
    required this.valor,
    this.motivo,
    this.autorizadaPor,
    this.cobrada = false,
  });

  factory CortesiaItemModel.fromJson(Map<String, dynamic> j) => CortesiaItemModel(
        fecha: DateTime.tryParse(j['fecha']?.toString() ?? '') ?? DateTime.now(),
        numeroOrden: (j['numeroOrden'] as num?)?.toInt(),
        lugar: j['lugar']?.toString() ?? '',
        plato: j['plato']?.toString() ?? '',
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 0,
        valor: ReporteCajasDiaModel._d(j['valor']),
        motivo: j['motivo']?.toString(),
        autorizadaPor: j['autorizadaPor']?.toString(),
        cobrada: j['cobrada'] == true,
      );
}

class ReporteCortesiasModel {
  final String nombreSucursal;
  final int totalUnidades;
  final double totalValor;
  final List<CortesiaItemModel> items;

  const ReporteCortesiasModel({
    required this.nombreSucursal,
    required this.totalUnidades,
    required this.totalValor,
    required this.items,
  });

  factory ReporteCortesiasModel.fromJson(Map<String, dynamic> j) => ReporteCortesiasModel(
        nombreSucursal: j['nombreSucursal']?.toString() ?? '',
        totalUnidades: (j['totalUnidades'] as num?)?.toInt() ?? 0,
        totalValor: ReporteCajasDiaModel._d(j['totalValor']),
        items: ((j['items'] as List?) ?? []).map((e) => CortesiaItemModel.fromJson(e)).toList(),
      );
}

/// Lo recaudado en propinas por un mesero en el período.
class PropinaMeseroModel {
  final String usuarioId;
  final String mesero;
  final int comprobantes;
  final double total;

  const PropinaMeseroModel({
    required this.usuarioId,
    required this.mesero,
    required this.comprobantes,
    required this.total,
  });

  factory PropinaMeseroModel.fromJson(Map<String, dynamic> j) => PropinaMeseroModel(
        usuarioId:    j['usuarioId']?.toString() ?? '',
        mesero:       j['mesero']?.toString() ?? '',
        comprobantes: (j['comprobantes'] as num?)?.toInt() ?? 0,
        total:        ReporteCajasDiaModel._d(j['total']),
      );
}

/// Propinas cobradas en el período. El backend manda también el desglose por
/// mesero; hoy la pantalla muestra solo el total, pero el dato ya viene.
class ReportePropinasModel {
  final String nombreSucursal;
  final double totalPropinas;
  final int comprobantesConPropina;
  final List<PropinaMeseroModel> porMesero;

  const ReportePropinasModel({
    required this.nombreSucursal,
    required this.totalPropinas,
    required this.comprobantesConPropina,
    required this.porMesero,
  });

  factory ReportePropinasModel.fromJson(Map<String, dynamic> j) => ReportePropinasModel(
        nombreSucursal:         j['nombreSucursal']?.toString() ?? '',
        totalPropinas:          ReporteCajasDiaModel._d(j['totalPropinas']),
        comprobantesConPropina: (j['comprobantesConPropina'] as num?)?.toInt() ?? 0,
        porMesero: ((j['porMesero'] as List?) ?? [])
            .map((m) => PropinaMeseroModel.fromJson(m))
            .toList(),
      );
}

class ReportesRepository {
  final _dio = ApiClient.instance.dio;

  static String _fechaParam(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';

  Future<ResumenDiarioModel> getResumenDiario(String sucursalId, {DateTime? fecha}) async {
    final r = await _dio.get('/api/reportes/resumen-diario', queryParameters: {
      'sucursalId': sucursalId,
      if (fecha != null) 'fecha': _fechaParam(fecha),
    });
    return ResumenDiarioModel.fromJson(r.data['data'] ?? r.data);
  }

  // Reporte de caja del día (solo admin): cada turno con su detalle completo
  Future<ReporteCajasDiaModel> getCierresCajaDia(String sucursalId, {DateTime? fecha}) async {
    final r = await _dio.get('/api/reportes/cierres-caja', queryParameters: {
      'sucursalId': sucursalId,
      if (fecha != null) 'fecha': _fechaParam(fecha),
    });
    return ReporteCajasDiaModel.fromJson(r.data['data'] ?? r.data);
  }

  // Cortesías de la sucursal en un período (solo admin)
  Future<ReporteCortesiasModel> getCortesias(
    String sucursalId, {
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final r = await _dio.get('/api/cortesias/reporte', queryParameters: {
      'sucursalId': sucursalId,
      'desde': _fechaParam(desde),
      'hasta': _fechaParam(hasta),
    });
    return ReporteCortesiasModel.fromJson(r.data['data'] ?? r.data);
  }

  // Órdenes anuladas de la sucursal en un período (solo admin)
  Future<ReporteOrdenesAnuladasModel> getOrdenesAnuladas(
    String sucursalId, {
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final r = await _dio.get('/api/reportes/ordenes-anuladas', queryParameters: {
      'sucursalId': sucursalId,
      'desde': _fechaParam(desde),
      'hasta': _fechaParam(hasta),
    });
    return ReporteOrdenesAnuladasModel.fromJson(r.data['data'] ?? r.data);
  }

  // Comparativo de ventas por sucursal en un período (solo admin)
  Future<ReporteVentasSucursalesModel> getVentasPorSucursal(
    String restaurantId, {
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final r = await _dio.get('/api/reportes/ventas-por-sucursal', queryParameters: {
      'restaurantId': restaurantId,
      'desde': _fechaParam(desde),
      'hasta': _fechaParam(hasta),
    });
    return ReporteVentasSucursalesModel.fromJson(r.data['data'] ?? r.data);
  }

  // Propinas cobradas en un período (solo admin): total a repartir entre los
  // meseros, con el desglose por mesero incluido en la respuesta.
  Future<ReportePropinasModel> getPropinas(
    String sucursalId, {
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final r = await _dio.get('/api/reportes/propinas', queryParameters: {
      'sucursalId': sucursalId,
      'desde': _fechaParam(desde),
      'hasta': _fechaParam(hasta),
    });
    return ReportePropinasModel.fromJson(r.data['data'] ?? r.data);
  }
}
