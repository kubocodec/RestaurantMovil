import '../../../core/models/caja_model.dart';
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
}
