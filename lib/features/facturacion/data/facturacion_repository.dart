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

  // Registrar cliente nuevo (queda vinculado a la sucursal del usuario)
  Future<ClienteModel> crearCliente({
    required String nombre,
    String? cedulaRuc,
    String? email,
    String? telefono,
  }) async {
    final r = await _dio.post('/api/clientes', data: {
      'nombre': nombre,
      if (cedulaRuc != null && cedulaRuc.isNotEmpty) 'cedulaRuc': cedulaRuc,
      if (email != null && email.isNotEmpty)         'email':     email,
      if (telefono != null && telefono.isNotEmpty)   'telefono':  telefono,
    });
    return ClienteModel.fromJson(r.data['data'] ?? r.data);
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

  /// Historial de comprobantes (facturas y recibos) de la sucursal en un día.
  Future<List<FacturaModel>> getComprobantes(String sucursalId, {DateTime? fecha}) async {
    final r = await _dio.get('/api/facturas/sucursal/$sucursalId', queryParameters: {
      if (fecha != null)
        'fecha': '${fecha.year.toString().padLeft(4, '0')}-'
            '${fecha.month.toString().padLeft(2, '0')}-'
            '${fecha.day.toString().padLeft(2, '0')}',
    });
    final List data = r.data['data'] ?? [];
    return data.map((j) => FacturaModel.fromJson(j)).toList();
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
