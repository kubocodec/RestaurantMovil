import '../../../core/models/factura_model.dart';
import '../../../core/network/api_client.dart';

class FacturacionRepository {
  final _dio = ApiClient.instance.dio;

  Future<List<MetodoPagoModel>> getMetodosPago() async {
    final r = await _dio.get('/api/metodos-pago/activos');
    final List data = r.data['data'] ?? [];
    return data.map((j) => MetodoPagoModel.fromJson(j)).toList();
  }

  Future<ClienteModel?> buscarClientePorCedula(String cedula) async {
    try {
      final r = await _dio.get('/api/clientes/cedula/$cedula');
      final d = r.data['data'];
      if (d == null) return null;
      return ClienteModel.fromJson(d);
    } catch (_) {
      return null;
    }
  }

  // Emitir factura (requiere aperturaCierreCajaId)
  Future<FacturaModel> emitirFactura({
    required String ordenId,
    required String aperturaCierreCajaId,
    String? clienteId,
    required List<Map<String, dynamic>> detalles, // [{ordenDetalleId, cantidad}]
    double descuento = 0,
    double propina = 0,
    String? notas,
  }) async {
    final r = await _dio.post('/api/facturas', data: {
      'ordenId':               ordenId,
      'aperturaCierreCajaId':  aperturaCierreCajaId,
      if (clienteId != null) 'clienteId': clienteId,
      'detalles':  detalles,
      'descuento': descuento,
      'propina':   propina,
      if (notas != null) 'notas': notas,
    });
    return FacturaModel.fromJson(r.data['data'] ?? r.data);
  }

  // Registrar pago de factura
  Future<FacturaModel> registrarPago({
    required String facturaVentaId,
    required String metodoPagoId,
    required double monto,
    String? referencia,
  }) async {
    final r = await _dio.post('/api/facturas/$facturaVentaId/pagos', data: {
      'metodoPagoId': metodoPagoId,
      'monto':        monto,
      if (referencia != null && referencia.isNotEmpty) 'referencia': referencia,
    });
    return FacturaModel.fromJson(r.data['data'] ?? r.data);
  }
}
