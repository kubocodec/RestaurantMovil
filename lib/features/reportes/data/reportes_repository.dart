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

class ReportesRepository {
  final _dio = ApiClient.instance.dio;

  Future<ResumenDiarioModel> getResumenDiario(String sucursalId, {DateTime? fecha}) async {
    final r = await _dio.get('/api/reportes/resumen-diario', queryParameters: {
      'sucursalId': sucursalId,
      if (fecha != null)
        'fecha': '${fecha.year.toString().padLeft(4, '0')}-'
            '${fecha.month.toString().padLeft(2, '0')}-'
            '${fecha.day.toString().padLeft(2, '0')}',
    });
    return ResumenDiarioModel.fromJson(r.data['data'] ?? r.data);
  }
}
