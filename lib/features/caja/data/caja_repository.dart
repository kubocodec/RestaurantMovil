import '../../../core/models/caja_model.dart';
import '../../../core/network/api_client.dart';

class CajaRepository {
  final _dio = ApiClient.instance.dio;

  Future<List<CajaModel>> getCajasBySucursal(String sucursalId) async {
    final r = await _dio.get('/api/caja/sucursal/$sucursalId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => CajaModel.fromJson(j)).toList();
  }

  // Obtiene la apertura activa de una caja (null si está cerrada)
  Future<AperturaCajaModel?> getAperturaActiva(String cajaId) async {
    try {
      final r = await _dio.get('/api/caja/$cajaId/activa');
      final d = r.data['data'];
      if (d == null) return null;
      return AperturaCajaModel.fromJson(d);
    } catch (_) {
      return null;
    }
  }

  Future<AperturaCajaModel> abrirCaja({
    required String cajaId,
    required double montoInicial,
    String? observaciones,
  }) async {
    final r = await _dio.post('/api/caja/abrir', data: {
      'cajaId':       cajaId,
      'montoInicial': montoInicial,
      if (observaciones != null) 'observaciones': observaciones,
    });
    return AperturaCajaModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<AperturaCajaModel> cerrarCaja({
    required String aperturaCierreCajaId,
    required double montoFinal,
    String? observaciones,
  }) async {
    final r = await _dio.post('/api/caja/$aperturaCierreCajaId/cerrar', data: {
      'montoFinal':   montoFinal,
      if (observaciones != null) 'observaciones': observaciones,
    });
    return AperturaCajaModel.fromJson(r.data['data'] ?? r.data);
  }

  // Estado en vivo de la apertura: esperado + movimientos
  Future<ResumenCajaModel> getResumen(String aperturaCierreCajaId) async {
    final r = await _dio.get('/api/caja/apertura/$aperturaCierreCajaId/resumen');
    return ResumenCajaModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<void> registrarMovimiento({
    required String aperturaCierreCajaId,
    required String tipo,    // INGRESO | EGRESO
    required double monto,
    required String concepto,
  }) async {
    await _dio.post('/api/caja/$aperturaCierreCajaId/movimientos', data: {
      'tipo':     tipo,
      'monto':    monto,
      'concepto': concepto,
    });
  }
}
